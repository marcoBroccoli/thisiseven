package api

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	"image/draw"
	"image/jpeg"
	_ "image/png"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

const (
	maxAvatarEdge    = 512
	maxAvatarBytes   = 500 << 10 // 500 KiB after encode
	maxAvatarUpload  = 2 << 20   // raw multipart budget before process
	avatarFormField  = "avatar"
	avatarJPEGQual   = 85
)

// processAvatarImage decodes JPEG/PNG, fits within maxAvatarEdge, and re-encodes
// as JPEG ≤ maxAvatarBytes.
func processAvatarImage(raw []byte) ([]byte, error) {
	if len(raw) == 0 {
		return nil, errors.New("empty image")
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, fmt.Errorf("unsupported image: %w", err)
	}
	img = fitAvatar(img, maxAvatarEdge)

	qual := avatarJPEGQual
	for qual >= 60 {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: qual}); err != nil {
			return nil, err
		}
		if buf.Len() <= maxAvatarBytes {
			return buf.Bytes(), nil
		}
		qual -= 10
	}
	return nil, errors.New("image too large after compression")
}

func fitAvatar(img image.Image, maxEdge int) image.Image {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= 0 || h <= 0 {
		return img
	}
	if w <= maxEdge && h <= maxEdge {
		return ensureRGBA(img)
	}
	scale := float64(maxEdge) / math.Max(float64(w), float64(h))
	nw := int(math.Round(float64(w) * scale))
	nh := int(math.Round(float64(h) * scale))
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	src := ensureRGBA(img)
	for y := 0; y < nh; y++ {
		sy := b.Min.Y + int(float64(y)*float64(h)/float64(nh))
		for x := 0; x < nw; x++ {
			sx := b.Min.X + int(float64(x)*float64(w)/float64(nw))
			dst.Set(x, y, src.At(sx, sy))
		}
	}
	return dst
}

func ensureRGBA(img image.Image) *image.RGBA {
	if rgba, ok := img.(*image.RGBA); ok {
		return rgba
	}
	b := img.Bounds()
	rgba := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	draw.Draw(rgba, rgba.Bounds(), img, b.Min, draw.Src)
	return rgba
}

func (a *API) avatarAbsPath(rel string) (string, error) {
	if a.AvatarDir == "" {
		return "", errors.New("avatar storage not configured")
	}
	if rel == "" || strings.Contains(rel, "..") || filepath.Base(rel) != rel {
		return "", errors.New("invalid avatar path")
	}
	return filepath.Join(a.AvatarDir, rel), nil
}

func (a *API) loadMemberJSON(ctx context.Context, memberID, meID string) (MemberJSON, error) {
	var m MemberJSON
	var path *string
	err := a.DB.QueryRow(ctx, `
		select id, display_name, color, avatar_path
		from members where id = $1`, memberID).
		Scan(&m.ID, &m.DisplayName, &m.Color, &path)
	if err != nil {
		return m, err
	}
	m.Color = canonicalizeMemberColor(m.Color)
	m.IsMe = m.ID == meID
	m.HasAvatar = path != nil && *path != ""
	return m, nil
}

// PUT /v1/me/avatar — multipart field "avatar" (JPEG or PNG).
func (a *API) PutAvatar(w http.ResponseWriter, r *http.Request) {
	if a.AvatarDir == "" {
		httpx.Error(w, http.StatusServiceUnavailable, "avatars_disabled", "avatar storage not configured")
		return
	}
	m := membership(r)
	if err := r.ParseMultipartForm(maxAvatarUpload); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_multipart", "expected multipart form with avatar")
		return
	}
	file, _, err := r.FormFile(avatarFormField)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "missing_avatar", "avatar file is required")
		return
	}
	defer file.Close()

	raw, err := io.ReadAll(io.LimitReader(file, maxAvatarUpload+1))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_avatar", "could not read avatar")
		return
	}
	if len(raw) > maxAvatarUpload {
		httpx.Error(w, http.StatusRequestEntityTooLarge, "avatar_too_large", "avatar is too large")
		return
	}
	jpegBytes, err := processAvatarImage(raw)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_avatar", err.Error())
		return
	}

	rel := m.MemberID + ".jpg"
	abs, err := a.avatarAbsPath(rel)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "avatar path failed")
		return
	}
	if err := os.MkdirAll(a.AvatarDir, 0o755); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not prepare avatar storage")
		return
	}
	tmp := abs + ".tmp"
	if err := os.WriteFile(tmp, jpegBytes, 0o644); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store avatar")
		return
	}
	if err := os.Rename(tmp, abs); err != nil {
		_ = os.Remove(tmp)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store avatar")
		return
	}

	now := time.Now().UTC()
	_, err = a.DB.Exec(r.Context(), `
		update members set avatar_path = $1, avatar_updated_at = $2 where id = $3`,
		rel, now, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not update avatar")
		return
	}

	out, err := a.loadMemberJSON(r.Context(), m.MemberID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, out)
}

// DELETE /v1/me/avatar — clear the caller's photo.
func (a *API) DeleteAvatar(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	var path *string
	err := a.DB.QueryRow(r.Context(),
		`select avatar_path from members where id = $1`, m.MemberID).Scan(&path)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	_, err = a.DB.Exec(r.Context(), `
		update members set avatar_path = null, avatar_updated_at = null where id = $1`,
		m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not clear avatar")
		return
	}
	if path != nil && *path != "" {
		if abs, err := a.avatarAbsPath(*path); err == nil {
			_ = os.Remove(abs)
		}
	}
	out, err := a.loadMemberJSON(r.Context(), m.MemberID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, out)
}

// GET /v1/members/{id}/avatar — household-gated JPEG.
func (a *API) GetMemberAvatar(w http.ResponseWriter, r *http.Request) {
	me := membership(r)
	memberID := chi.URLParam(r, "id")
	if memberID == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_id", "member id required")
		return
	}

	var (
		path      *string
		updatedAt *time.Time
		hh        string
	)
	err := a.DB.QueryRow(r.Context(), `
		select household_id, avatar_path, avatar_updated_at
		from members where id = $1`, memberID).
		Scan(&hh, &path, &updatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "member not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	if hh != me.HouseholdID {
		httpx.Error(w, http.StatusForbidden, "forbidden", "not in your household")
		return
	}
	if path == nil || *path == "" {
		httpx.Error(w, http.StatusNotFound, "no_avatar", "no avatar")
		return
	}
	abs, err := a.avatarAbsPath(*path)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "avatar path failed")
		return
	}

	etag := `"` + memberID
	if updatedAt != nil {
		etag += "-" + fmt.Sprintf("%d", updatedAt.Unix())
	}
	etag += `"`
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "private, max-age=3600")
	if match := r.Header.Get("If-None-Match"); match != "" && match == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}

	f, err := os.Open(abs)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "no_avatar", "avatar missing on disk")
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "image/jpeg")
	http.ServeContent(w, r, "avatar.jpg", timeOrNow(updatedAt), f)
}

func timeOrNow(t *time.Time) time.Time {
	if t != nil {
		return *t
	}
	return time.Now().UTC()
}
