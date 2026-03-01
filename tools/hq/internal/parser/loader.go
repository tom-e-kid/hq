package parser

import (
	"time"

	"github.com/tom-e-kid/hq/tools/hq/internal/model"
)

// LoadAll loads all dashboard data from the given base path.
// taskFiles specifies which task files to load with their roles.
func LoadAll(basePath string, now time.Time, taskFiles []TaskFileRole) (model.DashboardData, error) {
	data := model.DashboardData{
		Date: now,
	}

	milestones, err := LoadMilestones(basePath, now)
	if err != nil {
		return data, err
	}
	data.Milestones = milestones
	data.MilestoneFilePath = MilestoneFilePath(basePath)

	wip, err := LoadWIP()
	if err != nil {
		return data, err
	}
	data.WIPEntries = wip

	projects, err := LoadAllProjectTasks(basePath, taskFiles, now)
	if err != nil {
		return data, err
	}
	data.ProjectTasks = projects

	monthly, err := LoadMonthly(basePath, now)
	if err != nil {
		return data, err
	}
	data.Monthly = monthly

	allMonthly, err := LoadAllMonthly(basePath)
	if err != nil {
		return data, err
	}
	data.AllMonthly = allMonthly

	words, err := LoadWords(basePath)
	if err != nil {
		return data, err
	}
	data.Words = words

	return data, nil
}
