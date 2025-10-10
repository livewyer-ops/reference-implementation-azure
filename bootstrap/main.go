package main

import (
	"fmt"
	"math/rand"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

const (
	logo = `
 ███████   ███    ██    ██████    ███████
██         ████   ██   ██    ██
██         ██ ██  ██   ██    ██   █████
██         ██  ██ ██   ██    ██
 ███████   ██   ████    ██████    ███████
`
	bannerText = `
Cloud Native Operational Excellence
https://cnoe.io

`
	mainColor      = "#235588" // RGB Hex color: CNOE Blue
	highlightColor = "#4DABE8" // RGB Hex color: CNOE Light Blue
)

var tasks = []string{
	"kind create cluster",
	"kubectl apply",
	"a",
	"b",
	"c",
	"d",
	"e",
	"f",
	"g",
	"h",
	"i",
	"j",
}

// Styles
var (
	mainColorStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(mainColor))
	highlightStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(highlightColor))
	boldStyle      = lipgloss.NewStyle().Bold(true)
	checkMarkStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("46")).SetString("✓")
)

type task struct {
	description string
	command     string
}

type model struct {
	tasks    []string
	index    int
	width    int
	height   int
	spinner  spinner.Model
	progress progress.Model
	done     bool
}

func newModel() model {
	// Progress
	p := progress.New(
		progress.WithGradient(mainColor, highlightColor),
		progress.WithWidth(40),
		progress.WithoutPercentage(),
	)
	s := spinner.New()
	s.Style = highlightStyle
	return model{
		tasks:    tasks,
		spinner:  s,
		progress: p,
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(downloadAndInstall(m.tasks[m.index]), m.spinner.Tick)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc", "q":
			return m, tea.Quit
		}
	case installedPkgMsg:
		pkg := m.tasks[m.index]
		if m.index >= len(m.tasks)-1 {
			// Everything's been installed. We're done!
			m.done = true
			return m, tea.Sequence(
				tea.Printf("%s %s", checkMarkStyle, pkg), // print the last success message
				tea.Quit,                                 // exit the program
			)
		}

		// Update progress bar
		m.index++
		progressCmd := m.progress.SetPercent(float64(m.index) / float64(len(m.tasks)))

		return m, tea.Batch(
			progressCmd,
			tea.Printf("%s %s", checkMarkStyle, pkg), // print success message above our program
			downloadAndInstall(m.tasks[m.index]),     // download the next package
		)
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	case progress.FrameMsg:
		newModel, cmd := m.progress.Update(msg)
		if newModel, ok := newModel.(progress.Model); ok {
			m.progress = newModel
		}
		return m, cmd
	}
	return m, nil
}

func (m model) View() string {
	n := len(m.tasks)
	w := lipgloss.Width(fmt.Sprintf("%d", n))

	if m.done {
		return boldStyle.Render(fmt.Sprintf("\nDone! Executed %d tasks.\n", n))
	}

	taskCount := fmt.Sprintf(" %*d/%*d", w, m.index, w, n)

	spin := m.spinner.View() + " "
	prog := m.progress.View()
	cellsAvail := max(0, m.width-lipgloss.Width(spin+prog+taskCount))

	taskName := highlightStyle.Render(m.tasks[m.index])
	info := lipgloss.NewStyle().MaxWidth(cellsAvail).Render("Executing: " + taskName)

	cellsRemaining := max(0, m.width-lipgloss.Width(spin+info+prog+taskCount))
	gap := strings.Repeat(" ", cellsRemaining)

	return spin + info + gap + prog + taskCount
}

type installedPkgMsg string

func downloadAndInstall(pkg string) tea.Cmd {
	// This is where you'd do i/o stuff to download and install packages. In
	// our case we're just pausing for a moment to simulate the process.
	d := time.Millisecond * time.Duration(rand.Intn(2000)) //nolint:gosec
	return tea.Tick(d, func(t time.Time) tea.Msg {
		return installedPkgMsg(pkg)
	})
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func main() {
	// First, print banner
	fmt.Println(mainColorStyle.Render(logo))
	fmt.Println(boldStyle.Render(bannerText))

	// Run BubbleTea program
	if _, err := tea.NewProgram(newModel()).Run(); err != nil {
		fmt.Println("Error running program:", err)
		os.Exit(1)
	}
}
