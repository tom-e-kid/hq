package cmd

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/tom-e-kid/hq/tools/hq/internal/config"
	"github.com/tom-e-kid/hq/tools/hq/internal/parser"
)

// resolvedProject holds the result of project resolution from cwd.
type resolvedProject struct {
	org        string
	project    string
	projectDir string // directory containing tasks.md / notes/
}

// resourcePath returns the full path for a resource within this project.
func (rp resolvedProject) resourcePath(res config.Resource) string {
	return filepath.Join(rp.projectDir, res.Name)
}

// resourcePaths returns all paths for resources of the given type within this project.
func (rp resolvedProject) resourcePaths(cfg config.Settings, resType string) []string {
	var paths []string
	for _, r := range cfg.GetResources() {
		if r.Type == resType {
			paths = append(paths, filepath.Join(rp.projectDir, r.Name))
		}
	}
	return paths
}

// resolveProject resolves the target project from cwd.
// It scans projects/*/README.md for repo: fields, resolves them to
// filesystem paths, and checks if cwd is inside one of them.
// Falls back to inbox if no match.
func resolveProject(basePath string) resolvedProject {
	cwd, err := os.Getwd()
	if err != nil {
		return inboxFallback(basePath)
	}

	// Glob for all project README.md files
	pattern := filepath.Join(basePath, "projects", "*", "*", "README.md")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return inboxFallback(basePath)
	}

	homeDir, _ := os.UserHomeDir()
	srcRoot := filepath.Join(homeDir, "dev", "src")

	for _, readmePath := range matches {
		data, err := os.ReadFile(readmePath)
		if err != nil {
			continue
		}
		fm, _, err := parser.ExtractFrontmatter(string(data))
		if err != nil || fm == nil {
			continue
		}
		repo, ok := fm["repo"].(string)
		if !ok || repo == "" {
			continue
		}

		// Resolve repo to filesystem path
		repoPath := filepath.Join(srcRoot, repo)
		if !strings.HasPrefix(cwd, repoPath) {
			continue
		}

		// Extract org/project from path: .../projects/{org}/{project}/README.md
		rel, _ := filepath.Rel(filepath.Join(basePath, "projects"), readmePath)
		parts := strings.Split(rel, string(filepath.Separator))
		if len(parts) < 3 {
			continue
		}

		return resolvedProject{
			org:        parts[0],
			project:    parts[1],
			projectDir: filepath.Dir(readmePath),
		}
	}

	return inboxFallback(basePath)
}

func inboxFallback(basePath string) resolvedProject {
	return resolvedProject{
		org:        "_",
		project:    "inbox",
		projectDir: filepath.Join(basePath, "projects", "_", "inbox"),
	}
}
