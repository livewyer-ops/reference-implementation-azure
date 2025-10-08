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
	authorUrl = "https://livewyer.io"
	logo      = `
.____    .___ __      __________________.___._____________________
|    |   |   /  \    /  \_   _____/\__  |   |\_   _____/\______   \
|    |   |   \   \/\/   /|    __)_  /   |   | |    __)_  |       _/
|    |___|   |\        / |        \ \____   | |        \ |    |   \
|_______ \___| \__/\  / /_______  / / ______|/_______  / |____|_  /
       \/          \/          \/  \/               \/         \/
`

	ansiColor     = "\033[32m" // ANSI color: Green
	lipglossColor = "2"        // Lipgloss color: Green
	ansiReset     = "\033[0m"  // ANSI escape sequence for reset
)

func printBanner() {
	fmt.Println(ansiReset + ansiColor + logo + ansiReset)
	var centerStyle = lipgloss.NewStyle().Width(67).Bold(true).Align(lipgloss.Center)
	fmt.Println(centerStyle.Render(authorUrl + "\n"))
}

var requirements = []string{
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

var tasks = []string{
	"a",
	"b",
}

func main() {
	// First, print banner
	printBanner()

	// Run BubbleTea program
	if _, err := tea.NewProgram(newModel()).Run(); err != nil {
		fmt.Println("Error running program:", err)
		os.Exit(1)
	}
}

type model struct {
	requirements []string
	tasks        []string
	index        int
	width        int
	height       int
	spinner      spinner.Model
	progress     progress.Model
	done         bool
}

var (
	currentPkgNameStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(lipglossColor))
	doneStyle           = lipgloss.NewStyle().Margin(1, 2)
	checkMark           = lipgloss.NewStyle().Foreground(lipgloss.Color(lipglossColor)).SetString("✓")
)

func newModel() model {
	p := progress.New(
		progress.WithGradient("#132a21", "#63D3A6"),
		progress.WithWidth(40),
		progress.WithoutPercentage(),
	)
	s := spinner.New()
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("14")) // color: blue
	return model{
		tasks:    requirements,
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
				tea.Printf("%s %s", checkMark, pkg), // print the last success message
				tea.Quit,                            // exit the program
			)
		}

		// Update progress bar
		m.index++
		progressCmd := m.progress.SetPercent(float64(m.index) / float64(len(m.tasks)))

		return m, tea.Batch(
			progressCmd,
			tea.Printf("%s %s", checkMark, pkg),  // print success message above our program
			downloadAndInstall(m.tasks[m.index]), // download the next package
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
		return doneStyle.Render(fmt.Sprintf("Done! Executed %d tasks.\n", n))
	}

	pkgCount := fmt.Sprintf(" %*d/%*d", w, m.index, w, n)

	spin := m.spinner.View() + " "
	prog := m.progress.View()
	cellsAvail := max(0, m.width-lipgloss.Width(spin+prog+pkgCount))

	pkgName := currentPkgNameStyle.Render(m.tasks[m.index])
	info := lipgloss.NewStyle().MaxWidth(cellsAvail).Render("Executing: " + pkgName)

	cellsRemaining := max(0, m.width-lipgloss.Width(spin+info+prog+pkgCount))
	gap := strings.Repeat(" ", cellsRemaining)

	return spin + info + gap + prog + pkgCount
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
