package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
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
}

func NewLogger(rawLevel string) *Logger {
	level, ok := logLevelAliases[strings.ToLower(strings.TrimSpace(rawLevel))]
	if !ok {
		level = LevelInfo
	}
	return &Logger{level: level}
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

	entry := map[string]any{
		"ts":     time.Now().UTC().Format(time.RFC3339Nano),
		"level":  levelString(level),
		"msg":    msg,
		"source": "agent",
	}

	for k, v := range fields {
		entry[k] = v
	}

	// Always write logs to stderr to avoid interfering with stdout
	// (especially important for MCP mode where stdout is used for JSON-RPC protocol)
	enc := json.NewEncoder(os.Stderr)
	if err := enc.Encode(entry); err != nil {
		fmt.Fprintf(os.Stderr, "failed to encode log: %v\n", err)
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
