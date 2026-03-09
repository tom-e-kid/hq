package config

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Resource defines a configurable project resource (task file or notes directory).
type Resource struct {
	Name string `json:"name"`
	Type string `json:"type"` // "tasks" or "notes"
	Role string `json:"role"`
}

// Settings holds the HQ configuration.
type Settings struct {
	DataDir   string            `json:"data_dir"`
	Resources []Resource        `json:"resources,omitempty"`
	Repos     map[string]string `json:"repos,omitempty"`

	// Deprecated: use Resources instead. Kept for backward compat parsing.
	TaskFile  string   `json:"task_file,omitempty"`
	NotesDirs []string `json:"notes_dirs,omitempty"`
}

var defaultResources = []Resource{
	{Name: "tasks.md", Type: "tasks", Role: "tasks"},
	{Name: "notes", Type: "notes", Role: "notes"},
}

// GetResources returns the configured resources, falling back to defaults.
// If the old task_file/notes_dirs fields are set, they are converted to resources.
func (s Settings) GetResources() []Resource {
	if len(s.Resources) > 0 {
		return s.Resources
	}
	// Backward compat: convert old fields
	if s.TaskFile != "" || len(s.NotesDirs) > 0 {
		var res []Resource
		taskName := "tasks.md"
		if s.TaskFile != "" {
			taskName = s.TaskFile
		}
		res = append(res, Resource{Name: taskName, Type: "tasks", Role: "tasks"})
		noteNames := []string{"notes"}
		if len(s.NotesDirs) > 0 {
			noteNames = s.NotesDirs
		}
		for i, name := range noteNames {
			role := name
			if i == 0 {
				role = "notes"
			}
			res = append(res, Resource{Name: name, Type: "notes", Role: role})
		}
		return res
	}
	return defaultResources
}

// TaskResources returns resources of type "tasks".
func (s Settings) TaskResources() []Resource {
	var result []Resource
	for _, r := range s.GetResources() {
		if r.Type == "tasks" {
			result = append(result, r)
		}
	}
	return result
}

// NotesResources returns resources of type "notes".
func (s Settings) NotesResources() []Resource {
	var result []Resource
	for _, r := range s.GetResources() {
		if r.Type == "notes" {
			result = append(result, r)
		}
	}
	return result
}

// ResourceByRole returns the resource with the given role, or nil if not found.
func (s Settings) ResourceByRole(role string) *Resource {
	for _, r := range s.GetResources() {
		if r.Role == role {
			res := r
			return &res
		}
	}
	return nil
}

// DefaultTaskResource returns the first tasks resource.
func (s Settings) DefaultTaskResource() Resource {
	for _, r := range s.GetResources() {
		if r.Type == "tasks" {
			return r
		}
	}
	return Resource{Name: "tasks.md", Type: "tasks", Role: "tasks"}
}

// DefaultNotesResource returns the first notes resource.
func (s Settings) DefaultNotesResource() Resource {
	for _, r := range s.GetResources() {
		if r.Type == "notes" {
			return r
		}
	}
	return Resource{Name: "notes", Type: "notes", Role: "notes"}
}

// TaskFileName returns the default task filename (for backward compat callers).
func (s Settings) TaskFileName() string {
	return s.DefaultTaskResource().Name
}

// NotesDirNames returns all notes directory names (for backward compat callers).
func (s Settings) NotesDirNames() []string {
	var names []string
	for _, r := range s.NotesResources() {
		names = append(names, r.Name)
	}
	if len(names) == 0 {
		return []string{"notes"}
	}
	return names
}

// HQDir returns the path to ~/.hq/.
func HQDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".hq")
}

// Load reads ~/.hq/settings.json and returns the settings.
// Returns zero-value Settings if the file does not exist.
func Load() Settings {
	dir := HQDir()
	if dir == "" {
		return Settings{}
	}
	data, err := os.ReadFile(filepath.Join(dir, "settings.json"))
	if err != nil {
		return Settings{}
	}
	var s Settings
	if err := json.Unmarshal(data, &s); err != nil {
		return Settings{}
	}
	return s
}

// LoadDataDir reads <dataDir>/.hq/settings.json and returns the settings.
// This is used to load project-level settings (e.g., repos mapping).
// Returns zero-value Settings if the file does not exist.
func LoadDataDir(dataDir string) Settings {
	data, err := os.ReadFile(filepath.Join(dataDir, ".hq", "settings.json"))
	if err != nil {
		return Settings{}
	}
	var s Settings
	if err := json.Unmarshal(data, &s); err != nil {
		return Settings{}
	}
	return s
}
