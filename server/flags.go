package main

import "flag"

type LaunchFlags struct {
	Minimized bool
	AutoStartMode AutoStartMode
}

func parseFlags() LaunchFlags {
	var minimized bool
	var autostart string
	flag.BoolVar(&minimized, "minimized", false, "Start minimized to tray")
	flag.StringVar(&autostart, "autostart", "", "Autostart mode: server|client")
	flag.Parse()

	mode := AutoStartModeServer
	if autostart == "client" {
		mode = AutoStartModeClient
	}
	return LaunchFlags{Minimized: minimized, AutoStartMode: mode}
}
