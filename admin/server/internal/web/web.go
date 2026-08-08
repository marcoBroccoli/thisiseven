// Package web serves the built SPA out of the binary.
//
// The dist directory is produced by `npm run build` in admin/web and copied
// here by the Dockerfile. A placeholder index.html is committed so `go build`
// and `go test` work on a checkout that has never run the frontend build.
package web

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var dist embed.FS

// Handler returns a file server that falls back to index.html for unknown
// paths — the client router owns /users/{id} and friends, and a hard refresh
// there must not 404.
func Handler() http.Handler {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		panic("embedded dist missing: " + err.Error())
	}
	files := http.FileServer(http.FS(sub))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clean := path.Clean(strings.TrimPrefix(r.URL.Path, "/"))
		if clean == "." || clean == "/" {
			clean = "index.html"
		}
		if _, err := fs.Stat(sub, clean); err != nil {
			// Unknown path → the SPA shell. index.html itself is never cached,
			// so a redeploy is picked up on the next navigation.
			serveIndex(w, r, sub)
			return
		}
		// Vite fingerprints everything under /assets, so those are immutable.
		if strings.HasPrefix(clean, "assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			w.Header().Set("Cache-Control", "no-cache")
		}
		files.ServeHTTP(w, r)
	})
}

func serveIndex(w http.ResponseWriter, r *http.Request, sub fs.FS) {
	body, err := fs.ReadFile(sub, "index.html")
	if err != nil {
		http.Error(w, "admin UI is not built", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	_, _ = w.Write(body)
	_ = r
}
