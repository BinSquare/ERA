package main

import (
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

func normalizeLanguage(language string) string {
	return strings.ToLower(strings.TrimSpace(language))
}

func sanitizeID(raw string) string {
	clean := whitespace.ReplaceAllString(strings.TrimSpace(raw), "-")
	return strings.ToLower(clean)
}
