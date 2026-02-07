package main

import (
	"fmt"
	"strings"
)

type StartupAction int

const (
	StartupActionNone StartupAction = iota
	StartupActionStartServer
	StartupActionConnectClient
)

func decideStartupAction(flags LaunchFlags, settings Settings) StartupAction {
	// `AutoStartActionEnabled` controls whether we auto-start server/connect client
	// when the app launches. This is intentionally NOT coupled to OS autostart.
	if !settings.AutoStartActionEnabled {
		return StartupActionNone
	}

	// CLI flags can force an action (mainly used by OS autostart / tray start).
	if flags.Minimized {
		if flags.AutoStartMode == AutoStartModeClient {
			return StartupActionConnectClient
		}
		return StartupActionStartServer
	}

	// Normal manual launch: follow settings.
	if settings.AutoStartMode == AutoStartModeClient {
		return StartupActionConnectClient
	}
	return StartupActionStartServer
}

func normalizeWSURL(u string) (string, error) {
	u = strings.TrimSpace(u)
	if u == "" {
		return "", fmt.Errorf("url is empty")
	}
	if strings.HasPrefix(u, "ws://") || strings.HasPrefix(u, "wss://") {
		return u, nil
	}
	return "", fmt.Errorf("invalid ws url")
}
