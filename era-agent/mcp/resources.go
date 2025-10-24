package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Resource represents an MCP resource
type Resource struct {
	URI         string `json:"uri"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	MIMEType    string `json:"mimeType,omitempty"`
}

// ResourceReadRequest represents a resources/read request
type ResourceReadRequest struct {
	URI string `json:"uri"`
}

// ResourceContent represents resource content
type ResourceContent struct {
	URI      string `json:"uri"`
	MIMEType string `json:"mimeType,omitempty"`
	Text     string `json:"text,omitempty"`
}

// handleResourcesList returns the list of available resources
func (s *Server) handleResourcesList(ctx context.Context, params json.RawMessage) (interface{}, error) {
	sessions := s.vmSvc.List()

	resources := []Resource{}

	for _, session := range sessions {
		sessionMap := session.(map[string]interface{})
		sessionID, _ := sessionMap["id"].(string)

		// Add session resource
		resources = append(resources, Resource{
			URI:         fmt.Sprintf("session://%s", sessionID),
			Name:        fmt.Sprintf("Session: %s", sessionID),
			Description: fmt.Sprintf("ERA Agent session running %s", sessionMap["language"]),
			MIMEType:    "application/json",
		})

		// Add files resource
		resources = append(resources, Resource{
			URI:         fmt.Sprintf("session://%s/files", sessionID),
			Name:        fmt.Sprintf("Files in %s", sessionID),
			Description: fmt.Sprintf("List of files in session %s", sessionID),
			MIMEType:    "application/json",
		})
	}

	return map[string]interface{}{
		"resources": resources,
	}, nil
}

// handleResourcesRead reads a resource
func (s *Server) handleResourcesRead(ctx context.Context, params json.RawMessage) (interface{}, error) {
	var req ResourceReadRequest
	if err := json.Unmarshal(params, &req); err != nil {
		return nil, fmt.Errorf("invalid resource read request: %w", err)
	}

	s.logger.Info("Reading resource", map[string]interface{}{
		"uri": req.URI,
	})

	// Parse URI
	// Format: session://<session_id> or session://<session_id>/files
	if len(req.URI) < 10 || req.URI[:10] != "session://" {
		return nil, fmt.Errorf("invalid URI format: %s", req.URI)
	}

	path := req.URI[10:] // Remove "session://"

	// Split path
	sessionID := path
	isFiles := false
	if len(path) > 0 {
		parts := filepath.SplitList(path)
		if len(parts) > 1 {
			sessionID = parts[0]
			if parts[1] == "files" {
				isFiles = true
			}
		}
	}

	// Get session
	session, exists := s.vmSvc.Get(sessionID)
	if !exists {
		return nil, fmt.Errorf("session not found: %s", sessionID)
	}

	if isFiles {
		return s.readFilesResource(sessionID)
	}

	return s.readSessionResource(session)
}

// readSessionResource reads session info as a resource
func (s *Server) readSessionResource(session interface{}) (interface{}, error) {
	sessionMap := session.(map[string]interface{})

	data, err := json.MarshalIndent(sessionMap, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to marshal session: %w", err)
	}

	return map[string]interface{}{
		"contents": []ResourceContent{
			{
				URI:      fmt.Sprintf("session://%s", sessionMap["id"]),
				MIMEType: "application/json",
				Text:     string(data),
			},
		},
	}, nil
}

// readFilesResource reads files list as a resource
func (s *Server) readFilesResource(sessionID string) (interface{}, error) {
	workDir := s.vmSvc.GetVMWorkDir(sessionID)
	if workDir == "" {
		return nil, fmt.Errorf("session not found: %s", sessionID)
	}

	var files []map[string]interface{}

	err := filepath.Walk(workDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			relPath, _ := filepath.Rel(workDir, path)
			files = append(files, map[string]interface{}{
				"path": relPath,
				"size": info.Size(),
			})
		}
		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to list files: %w", err)
	}

	data, err := json.MarshalIndent(files, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to marshal files: %w", err)
	}

	return map[string]interface{}{
		"contents": []ResourceContent{
			{
				URI:      fmt.Sprintf("session://%s/files", sessionID),
				MIMEType: "application/json",
				Text:     string(data),
			},
		},
	}, nil
}
