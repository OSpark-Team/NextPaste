package main

import (
	"errors"
	"os"
	"path/filepath"

	"github.com/emersion/go-autostart"
)

type AutoStartMode string

const (
	AutoStartModeServer AutoStartMode = "server"
	AutoStartModeClient AutoStartMode = "client"
)

type Settings struct {
	AutoStartEnabled       bool          `json:"autoStartEnabled"`
	AutoStartActionEnabled bool          `json:"autoStartActionEnabled"`
	AutoStartMode          AutoStartMode `json:"autoStartMode"`
	CloseAction            string        `json:"closeAction"` // "minimize" | "close"
}

func getExecPath() (string, error) {
	path, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(path)
}

func newAutostartApp(execPath string, mode AutoStartMode) (*autostart.App, error) {
	if execPath == "" {
		return nil, errors.New("exec path is empty")
	}

	exec := []string{execPath, "--minimized"}
	if mode == AutoStartModeClient {
		exec = append(exec, "--autostart=client")
	} else {
		exec = append(exec, "--autostart=server")
	}

	return &autostart.App{
		Name:        "NextPaste",
		DisplayName: "NextPaste Sync Tool",
		Exec:        exec,
	}, nil
}

// Autostart support on Windows relies on go-autostart's Windows implementation,
// which requires CGO (autostart_windows.go has `import "C"`).
//
// In this repo, the default dev toolchain has CGO disabled (CGO_ENABLED=0),
// so only the base App type is compiled and Enable/Disable/IsEnabled are
// unavailable.
func canUseAutostart() bool {
	return false
}
