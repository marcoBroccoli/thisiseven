package api

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/auth"
)

func TestProcessAvatarJPEGResizesAndCaps(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 1200, 800))
	for y := 0; y < 800; y++ {
		for x := 0; x < 1200; x++ {
			src.Set(x, y, color.RGBA{R: 180, G: 80, B: 40, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, src, &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}

	out, err := processAvatarImage(buf.Bytes())
	if err != nil {
		t.Fatalf("processAvatarImage: %v", err)
	}
	if len(out) == 0 {
		t.Fatal("empty output")
	}
	if len(out) > maxAvatarBytes {
		t.Fatalf("output %d exceeds max %d", len(out), maxAvatarBytes)
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatalf("decode output: %v", err)
	}
	b := img.Bounds()
	if b.Dx() > maxAvatarEdge || b.Dy() > maxAvatarEdge {
		t.Fatalf("size %dx%d exceeds %d", b.Dx(), b.Dy(), maxAvatarEdge)
	}
	if b.Dx() != maxAvatarEdge && b.Dy() != maxAvatarEdge {
		t.Fatalf("expected longest edge %d, got %dx%d", maxAvatarEdge, b.Dx(), b.Dy())
	}
}

func TestProcessAvatarPNGAccepted(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 64, 64))
	var buf bytes.Buffer
	if err := png.Encode(&buf, src); err != nil {
		t.Fatal(err)
	}
	out, err := processAvatarImage(buf.Bytes())
	if err != nil {
		t.Fatalf("processAvatarImage: %v", err)
	}
	if _, err := jpeg.Decode(bytes.NewReader(out)); err != nil {
		t.Fatalf("expected jpeg output: %v", err)
	}
}

func TestProcessAvatarRejectsGarbage(t *testing.T) {
	_, err := processAvatarImage([]byte("not an image"))
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestAvatarUploadServeDelete(t *testing.T) {
	dbURL := os.Getenv("EVEN_TESTDB")
	if dbURL == "" {
		t.Skip("EVEN_TESTDB not set")
	}
	secret := []byte(os.Getenv("EVEN_GOTRUE_JWT_SECRET"))
	if len(secret) == 0 {
		t.Fatal("EVEN_GOTRUE_JWT_SECRET required")
	}

	db, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	dir := t.TempDir()
	srv := httptest.NewServer(Router(&API{DB: db, AvatarDir: dir}, auth.NewVerifier(secret), "http://127.0.0.1:1"))
	defer srv.Close()

	ada := &client{t: t, base: srv.URL, token: mintToken(t, secret, newUUID())}
	code, body := ada.do("POST", "/v1/households", map[string]any{
		"name": "Avatar House", "display_name": "Ada",
	})
	mustStatus(t, code, 201, "create household", body)
	members := body["members"].([]any)
	adaID := members[0].(map[string]any)["id"].(string)

	var jpegBuf bytes.Buffer
	src := image.NewRGBA(image.Rect(0, 0, 80, 80))
	if err := jpeg.Encode(&jpegBuf, src, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatal(err)
	}

	var form bytes.Buffer
	w := multipart.NewWriter(&form)
	part, err := w.CreateFormFile("avatar", "me.jpg")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(jpegBuf.Bytes()); err != nil {
		t.Fatal(err)
	}
	_ = w.Close()

	req, _ := http.NewRequest("PUT", srv.URL+"/v1/me/avatar", &form)
	req.Header.Set("Authorization", "Bearer "+ada.token)
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		t.Fatalf("put avatar: %d %s", resp.StatusCode, b)
	}
	var putOut map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&putOut)
	if putOut["has_avatar"] != true {
		t.Fatalf("expected has_avatar: %v", putOut)
	}

	getReq, _ := http.NewRequest("GET", srv.URL+"/v1/members/"+adaID+"/avatar", nil)
	getReq.Header.Set("Authorization", "Bearer "+ada.token)
	getResp, err := http.DefaultClient.Do(getReq)
	if err != nil {
		t.Fatal(err)
	}
	defer getResp.Body.Close()
	if getResp.StatusCode != 200 {
		t.Fatalf("get avatar: %d", getResp.StatusCode)
	}
	if ct := getResp.Header.Get("Content-Type"); ct != "image/jpeg" {
		t.Fatalf("content-type: %s", ct)
	}
	raw, _ := io.ReadAll(getResp.Body)
	if _, err := jpeg.Decode(bytes.NewReader(raw)); err != nil {
		t.Fatalf("body not jpeg: %v", err)
	}

	code, delBody := ada.do("DELETE", "/v1/me/avatar", nil)
	mustStatus(t, code, 200, "delete avatar", delBody)
	if delBody["has_avatar"] != false {
		t.Fatalf("expected cleared: %v", delBody)
	}
	getResp2, err := http.DefaultClient.Do(getReq)
	if err != nil {
		t.Fatal(err)
	}
	defer getResp2.Body.Close()
	if getResp2.StatusCode != 404 {
		t.Fatalf("get after delete: %d", getResp2.StatusCode)
	}
}
