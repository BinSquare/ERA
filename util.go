package main

import (
	"errors"
	"os"
	"regexp"
	"strings"
)

var whitespace = regexp.MustCompile(`\s+`)

func getenvOrDefault(key, fallback string) string {
	val := os.Getenv(key)
	if strings.TrimSpace(val) == "" {
		return fallback
	}
	return val
}

func ensureDir(path string) error {
	if strings.TrimSpace(path) == "" {
		return errors.New("path is empty")
	}
	if err := os.MkdirAll(path, storageDirPerm); err != nil {
		return err
	}
	return os.Chmod(path, storageDirPerm)
}

func normalizeLanguage(language string) string {
	return strings.ToLower(strings.TrimSpace(language))
}

func sanitizeID(raw string) string {
	clean := whitespace.ReplaceAllString(strings.TrimSpace(raw), "-")
	return strings.ToLower(clean)
}
