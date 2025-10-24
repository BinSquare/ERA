package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type LogLevel int

const (
	LevelDebug LogLevel = iota
	LevelInfo
	LevelWarn
	LevelError
)

var logLevelAliases = map[string]LogLevel{
	"debug": LevelDebug,
	"info":  LevelInfo,
	"warn":  LevelWarn,
	"error": LevelError,
}

type Logger struct {
	level LogLevel
	file  *os.File
	mu    sync.Mutex
}

func NewLogger(rawLevel, logFile string) (*Logger, error) {
	level, ok := logLevelAliases[strings.ToLower(strings.TrimSpace(rawLevel))]
	if !ok {
		level = LevelInfo
	}

	var file *os.File
	if trimmed := strings.TrimSpace(logFile); trimmed != "" {
		dir := filepath.Dir(trimmed)
		if dir != "" && dir != "." {
			if err := ensureDir(dir); err != nil {
				return nil, fmt.Errorf("create log directory: %w", err)
			}
		}

		var err error
		file, err = os.OpenFile(trimmed, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o640)
		if err != nil {
			return nil, fmt.Errorf("open log file: %w", err)
		}
	}

	return &Logger{level: level, file: file}, nil
}

func (l *Logger) Close() error {
	if l == nil || l.file == nil {
		return nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	err := l.file.Close()
	l.file = nil
	return err
}

func (l *Logger) Debug(msg string, fields map[string]any) {
	l.log(LevelDebug, msg, fields)
}

func (l *Logger) Info(msg string, fields map[string]any) {
	l.log(LevelInfo, msg, fields)
}

func (l *Logger) Warn(msg string, fields map[string]any) {
	l.log(LevelWarn, msg, fields)
}

func (l *Logger) Error(msg string, fields map[string]any) {
	l.log(LevelError, msg, fields)
}

func (l *Logger) log(level LogLevel, msg string, fields map[string]any) {
	if level < l.level {
		return
	}

	ts := time.Now().UTC().Format(time.RFC3339)
	levelStr := strings.ToUpper(levelString(level))

	var builder strings.Builder
	builder.WriteString(ts)
	builder.WriteString(" ")
	builder.WriteString(levelStr)
	builder.WriteString(" ")
	builder.WriteString(msg)

	if len(fields) > 0 {
		keys := make([]string, 0, len(fields))
		for k := range fields {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, key := range keys {
			builder.WriteString(" ")
			builder.WriteString(key)
			builder.WriteString("=")
			builder.WriteString(formatFieldValue(fields[key]))
		}
	}

	builder.WriteString("\n")

	output := builder.String()
	if level >= LevelError {
		fmt.Fprint(os.Stderr, output)
	} else {
		fmt.Fprint(os.Stdout, output)
	}

	if l.file != nil {
		l.mu.Lock()
		_, _ = l.file.WriteString(output)
		l.mu.Unlock()
	}
}

func levelString(level LogLevel) string {
	switch level {
	case LevelDebug:
		return "debug"
	case LevelInfo:
		return "info"
	case LevelWarn:
		return "warn"
	case LevelError:
		return "error"
	default:
		return "info"
	}
}

func formatFieldValue(value any) string {
	if value == nil {
		return "null"
	}

	str := fmt.Sprintf("%v", value)
	if str == "" {
		return `""`
	}

	if needsQuoting(str) {
		return `"` + escapeString(str) + `"`
	}

	return str
}

func needsQuoting(s string) bool {
	for _, r := range s {
		if r <= 0x1F || r == '"' || r == '\\' || r == '=' || r == ' ' || r == '\t' {
			return true
		}
	}
	return false
}

func escapeString(s string) string {
	var builder strings.Builder
	for _, r := range s {
		switch r {
		case '\\':
			builder.WriteString(`\\`)
		case '"':
			builder.WriteString(`\"`)
		case '\n':
			builder.WriteString(`\n`)
		case '\r':
			builder.WriteString(`\r`)
		case '\t':
			builder.WriteString(`\t`)
		default:
			if r <= 0x1F {
				builder.WriteString(fmt.Sprintf(`\u%04x`, r))
			} else {
				builder.WriteRune(r)
			}
		}
	}
	return builder.String()
}
