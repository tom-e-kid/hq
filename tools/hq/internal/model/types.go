package model

import "time"

// Milestone represents a project milestone with an optional target date.
type Milestone struct {
	Content       string    `json:"content"`
	Date          time.Time `json:"date,omitempty"`
	RemainingDays int       `json:"remaining_days"`
	Done          int       `json:"done"`
	Total         int       `json:"total"`
	Checked       bool      `json:"checked"`
	HasDate       bool      `json:"has_date"`
	Recurring     bool      `json:"recurring"`
	RecurringRule string    `json:"recurring_rule"` // "@monthly 10", "@month-end", etc.
	FilePath      string    `json:"file_path"`
	Line          int       `json:"line"` // 1-based line number in source file
}

// Task represents a single checkbox task item.
type Task struct {
	Text          string    `json:"text"`
	Checked       bool      `json:"checked"`
	Date          time.Time `json:"date,omitempty"`
	RemainingDays int       `json:"remaining_days"`
	HasDate       bool      `json:"has_date"`
	Recurring     bool      `json:"recurring"`
	RecurringRule string    `json:"recurring_rule,omitempty"`
	FilePath      string    `json:"file_path"`
	Line          int       `json:"line"` // 1-based line number in source file
}

// ProjectTasks holds tasks grouped by project.
type ProjectTasks struct {
	Org     string `json:"org"`
	Project string `json:"project"`
	Role    string `json:"role,omitempty"` // resource role (e.g. "tasks", "backlog")
	Tasks   []Task `json:"tasks"`
}

// OpenCount returns the number of unchecked tasks.
func (pt ProjectTasks) OpenCount() int {
	count := 0
	for _, t := range pt.Tasks {
		if !t.Checked {
			count++
		}
	}
	return count
}

// DoneCount returns the number of checked tasks.
func (pt ProjectTasks) DoneCount() int {
	count := 0
	for _, t := range pt.Tasks {
		if t.Checked {
			count++
		}
	}
	return count
}

// NoteInfo holds metadata about a note file.
type NoteInfo struct {
	FileName string   `json:"file_name"`
	Dir      string   `json:"dir"`
	Title    string   `json:"title"`
	Date     string   `json:"date"`
	Tags     []string `json:"tags,omitempty"`
	Summary  string   `json:"summary,omitempty"`
}

// WIPEntry represents a work-in-progress task.
type WIPEntry struct {
	Project     string `json:"project"`
	Description string `json:"description"`
	Branch      string `json:"branch,omitempty"`
}

// TimeEntry represents a single time tracking entry.
type TimeEntry struct {
	Client   string  `json:"client"`
	Category string  `json:"category"`
	Hours    float64 `json:"hours"`
}

// DailyEntry represents a single day's log entry.
type DailyEntry struct {
	Date        time.Time   `json:"date"`
	TotalHours  float64     `json:"total_hours"`
	TimeEntries []TimeEntry `json:"time_entries"`
}

// ClientHours holds hours for a single client, derived from log entries.
type ClientHours struct {
	Client string  `json:"client"`
	Hours  float64 `json:"hours"`
}

// MonthlyData holds the parsed monthly log data.
type MonthlyData struct {
	Month        string        `json:"month"`
	TotalHours   float64       `json:"total_hours"`
	ClientHours  []ClientHours `json:"client_hours"`
	WorkingDays  int           `json:"working_days"`
	DailyEntries []DailyEntry  `json:"daily_entries"`
	Summary      string        `json:"summary,omitempty"`
}

// AvgHours returns the average hours per working day.
func (m MonthlyData) AvgHours() float64 {
	if m.WorkingDays == 0 {
		return 0
	}
	return m.TotalHours / float64(m.WorkingDays)
}

// DashboardData aggregates all data for the dashboard view.
type DashboardData struct {
	Date              time.Time      `json:"date"`
	Milestones        []Milestone    `json:"milestones"`
	MilestoneFilePath string         `json:"milestone_file_path"`
	WIPEntries        []WIPEntry     `json:"wip_entries"`
	ProjectTasks      []ProjectTasks `json:"project_tasks"`
	Monthly           MonthlyData    `json:"monthly"`
	AllMonthly        []MonthlyData  `json:"all_monthly"`
	Words             []string       `json:"words"`
}

// TotalOpenTasks returns the total number of open tasks across all projects.
func (d DashboardData) TotalOpenTasks() int {
	count := 0
	for _, pt := range d.ProjectTasks {
		count += pt.OpenCount()
	}
	return count
}
