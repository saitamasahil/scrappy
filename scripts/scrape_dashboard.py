import http.server
import socketserver
import json
import os
import sys
import base64
import argparse
import time
import threading

PORT = 8081
STATE_FILE = "/tmp/scrappy_dashboard.json"


def build_html(theme="dark", accent="cbaa0f", logo_b64=""):
    """Build the HTML dashboard with theme-aware styling."""
    is_dark = "light" not in theme.lower()

    themes = {
        "dark": {
            "bg": "#0a0a0f",
            "card_bg": "#16161e",
            "card_border": "#2a2a35",
            "text_primary": "#e4e4e8",
            "text_secondary": "#9a9aa8",
            "text_muted": "#6a6a78",
            "log_bg": "#0e0e16",
            "log_border": "#2a2a35",
            "stat_bg": "#1a1a24",
            "stat_border": "#2a2a35",
            "phase_fetch_bg": "#0f1a2a",
            "phase_fetch_border": "#1a3a5a",
            "phase_gen_bg": "#0f2a1a",
            "phase_gen_border": "#1a5a3a",
            "failed_bg": "#1a0f0f",
            "failed_border": "#3a1a1a",
            "failed_text": "#e85555",
            "success_text": "#4ade80",
            "logo_filter": "none",
            "ring_track": "#2a2a35",
            "overlay_bg": "rgba(0,0,0,0.6)"
        },
        "light": {
            "bg": "#f0f0f4",
            "card_bg": "#ffffff",
            "card_border": "#e0e0e5",
            "text_primary": "#1a1a2e",
            "text_secondary": "#6a6a7a",
            "text_muted": "#9a9aa8",
            "log_bg": "#f5f5f8",
            "log_border": "#e0e0e5",
            "stat_bg": "#f8f8fc",
            "stat_border": "#e8e8ed",
            "phase_fetch_bg": "#f0f5ff",
            "phase_fetch_border": "#c0d5f0",
            "phase_gen_bg": "#f0fff5",
            "phase_gen_border": "#c0f0d0",
            "failed_bg": "#fff5f5",
            "failed_border": "#f0c0c0",
            "failed_text": "#c02020",
            "success_text": "#22872d",
            "logo_filter": "invert(1)",
            "ring_track": "#e0e0e5",
            "overlay_bg": "rgba(255,255,255,0.6)"
        }
    }

    t = themes["dark"] if is_dark else themes["light"]

    # Define CSS variables based on theme
    css_vars = f"""
        :root {{
            --bg: {t['bg']};
            --card-bg: {t['card_bg']};
            --card-border: {t['card_border']};
            --text-primary: {t['text_primary']};
            --text-secondary: {t['text_secondary']};
            --text-muted: {t['text_muted']};
            --log-bg: {t['log_bg']};
            --log-border: {t['log_border']};
            --stat-bg: {t['stat_bg']};
            --stat-border: {t['stat_border']};
            --phase-fetch-bg: {t['phase_fetch_bg']};
            --phase-fetch-border: {t['phase_fetch_border']};
            --phase-gen-bg: {t['phase_gen_bg']};
            --phase-gen-border: {t['phase_gen_border']};
            --failed-bg: {t['failed_bg']};
            --failed-border: {t['failed_border']};
            --failed-text: {t['failed_text']};
            --success-text: {t['success_text']};
            --accent: #{accent};
            --logo-filter: {t['logo_filter']};
            --ring-track: {t['ring_track']};
            --overlay-bg: {t['overlay_bg']};
        }}
    """

    logo_section = ""
    if logo_b64:
        logo_section = f'''
        <div class="logo-container">
            <img src="data:image/png;base64,{logo_b64}" alt="Scrappy" class="logo" style="filter: {t['logo_filter']};">
        </div>'''

        template = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scrappy &mdash; Live Scraping Dashboard</title>
    <link rel="icon" type="image/png" href="data:image/png;base64,{logo_b64}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: var(--bg);
            color: var(--text-primary);
            min-height: 100vh;
            padding: 1rem;
            transition: background 0.4s ease, color 0.4s ease;
        }

        .page {
            width: 100%;
            max-width: 640px;
            margin: 0 auto;
            animation: fadeInUp 0.6s ease-out;
        }

        @keyframes fadeInUp {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        @keyframes logoReveal {
            0% { opacity: 0; transform: scale(0.8); }
            50% { opacity: 1; transform: scale(1.05); }
            100% { opacity: 1; transform: scale(1); }
        }

        @keyframes pulse {
            0%, 100% { opacity: 0.6; }
            50% { opacity: 1; }
        }

        @keyframes spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
        }

        @keyframes slideIn {
            from { opacity: 0; transform: translateX(-10px); }
            to { opacity: 1; transform: translateX(0); }
        }

        .logo-container {
            text-align: center;
            margin-bottom: 1rem;
        }

        .logo {
            height: 48px;
            animation: logoReveal 0.8s ease-out;
            filter: var(--logo-filter);
        }

        .header {
            text-align: center;
            margin-bottom: 1.25rem;
        }

        .header h1 {
            font-size: 1.2rem;
            font-weight: 600;
            letter-spacing: -0.01em;
            margin-bottom: 0.25rem;
        }

        .header .subtitle {
            font-size: 0.8rem;
            color: var(--text-secondary);
        }

        .accent-dot {
            display: inline-block;
            width: 8px;
            height: 8px;
            background: var(--accent);
            border-radius: 50%;
            margin-right: 6px;
            animation: pulse 2s ease-in-out infinite;
        }

        /* Progress Ring */
        .progress-section {
            display: flex;
            align-items: center;
            gap: 1.25rem;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 1.25rem 1.5rem;
            margin-bottom: 0.75rem;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .ring-container {
            position: relative;
            width: 90px;
            height: 90px;
            flex-shrink: 0;
        }

        .ring-container svg {
            transform: rotate(-90deg);
            width: 90px;
            height: 90px;
        }

        .ring-track {
            fill: none;
            stroke: var(--ring-track);
            stroke-width: 6;
        }

        .ring-progress {
            fill: none;
            stroke: var(--accent);
            stroke-width: 6;
            stroke-linecap: round;
            transition: stroke-dashoffset 0.5s ease;
        }

        .ring-label {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 1.3rem;
            font-weight: 700;
            color: var(--text-primary);
        }

        .ring-label .pct {
            font-size: 0.7rem;
            font-weight: 400;
            color: var(--text-secondary);
        }

        .progress-info {
            flex: 1;
            min-width: 0;
        }

        .progress-info h2 {
            font-size: 1rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
        }

        .progress-detail {
            font-size: 0.8rem;
            color: var(--text-secondary);
            margin-bottom: 0.25rem;
        }

        .progress-bar-bg {
            width: 100%;
            height: 6px;
            background: var(--ring-track);
            border-radius: 3px;
            margin-top: 0.5rem;
            overflow: hidden;
        }

        .progress-bar-fill {
            height: 100%;
            background: var(--accent);
            border-radius: 3px;
            transition: width 0.5s ease;
            width: 0%;
        }

        /* Stats Row */
        .stats-row {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 0.5rem;
            margin-bottom: 0.75rem;
        }

        .stat-card {
            background: var(--stat-bg);
            border: 1px solid var(--stat-border);
            border-radius: 12px;
            padding: 0.75rem 0.5rem;
            text-align: center;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .stat-value {
            font-size: 1.2rem;
            font-weight: 700;
            color: var(--text-primary);
            margin-bottom: 0.15rem;
        }

        .stat-label {
            font-size: 0.65rem;
            font-weight: 500;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        /* Current Game Card */
        .current-card {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 14px;
            padding: 1rem 1.25rem;
            margin-bottom: 0.75rem;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .current-card .card-title {
            font-size: 0.7rem;
            font-weight: 600;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.06em;
            margin-bottom: 0.6rem;
        }

        .current-item {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            margin-bottom: 0.5rem;
        }

        .current-item:last-child {
            margin-bottom: 0;
        }

        .current-icon {
            width: 28px;
            height: 28px;
            background: var(--stat-bg);
            border: 1px solid var(--stat-border);
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 0.85rem;
            flex-shrink: 0;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .current-text {
            flex: 1;
            min-width: 0;
        }

        .current-text .label {
            font-size: 0.7rem;
            color: var(--text-muted);
            margin-bottom: 0.1rem;
        }

        .current-text .value {
            font-size: 0.9rem;
            font-weight: 500;
            color: var(--text-primary);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .game-value {
            animation: slideIn 0.3s ease-out;
        }

        /* Phase Badge */
        .phase-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.75rem;
            font-weight: 600;
        }

        .phase-fetch {
            background: var(--phase-fetch-bg);
            border: 1px solid var(--phase-fetch-border);
            color: #5b9bf5;
        }

        .phase-gen {
            background: var(--phase-gen-bg);
            border: 1px solid var(--phase-gen-border);
            color: var(--success-text);
        }

        .phase-done {
            background: var(--phase-gen-bg);
            border: 1px solid var(--phase-gen-border);
            color: var(--success-text);
        }

        .phase-spinner {
            width: 10px;
            height: 10px;
            border: 2px solid transparent;
            border-top-color: currentColor;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }

        /* Log Section */
        .log-section {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 14px;
            padding: 1rem;
            margin-bottom: 0.75rem;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .log-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 0.6rem;
        }

        .log-header .card-title {
            font-size: 0.7rem;
            font-weight: 600;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }

        .log-count {
            font-size: 0.7rem;
            color: var(--text-muted);
        }

        .log-box {
            background: var(--log-bg);
            border: 1px solid var(--log-border);
            border-radius: 10px;
            padding: 0.75rem;
            max-height: 220px;
            overflow-y: auto;
            scroll-behavior: smooth;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .log-box::-webkit-scrollbar {
            width: 4px;
        }

        .log-box::-webkit-scrollbar-track {
            background: transparent;
        }

        .log-box::-webkit-scrollbar-thumb {
            background: var(--card-border);
            border-radius: 2px;
        }

        .log-line {
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.72rem;
            line-height: 1.6;
            color: var(--text-secondary);
            white-space: pre-wrap;
            word-break: break-all;
        }

        .log-line.found {
            color: var(--success-text);
        }

        .log-line.error {
            color: var(--failed-text);
        }

        .log-line.info {
            color: #5b9bf5;
        }

        /* Failed Games */
        .failed-section {
            background: var(--failed-bg);
            border: 1px solid var(--failed-border);
            border-radius: 14px;
            padding: 1rem;
            margin-bottom: 0.75rem;
            display: none;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .failed-section.visible {
            display: block;
        }

        .failed-header {
            font-size: 0.75rem;
            font-weight: 600;
            color: var(--failed-text);
            margin-bottom: 0.5rem;
        }

        .failed-list {
            list-style: none;
            padding: 0;
        }

        .failed-list li {
            font-size: 0.78rem;
            color: var(--failed-text);
            padding: 0.2rem 0;
            opacity: 0.85;
        }

        .failed-list li::before {
            content: "\\00d7";
            margin-right: 6px;
            font-weight: 700;
        }

        /* Idle / Complete Overlay */
        .idle-overlay {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 3rem 2rem;
            text-align: center;
            display: none;
            transition: background 0.4s ease, border-color 0.4s ease;
        }

        .idle-overlay.visible {
            display: block;
        }

        .idle-overlay .idle-icon {
            font-size: 2.5rem;
            margin-bottom: 1rem;
        }

        .idle-overlay h2 {
            font-size: 1.1rem;
            font-weight: 600;
            margin-bottom: 0.4rem;
        }

        .idle-overlay p {
            font-size: 0.85rem;
            color: var(--text-secondary);
        }

        .footer {
            text-align: center;
            margin-top: 1rem;
            font-size: 0.7rem;
            color: var(--text-secondary);
            opacity: 0.5;
        }

        /* Responsive */
        @media (max-width: 480px) {
            .stats-row {
                grid-template-columns: repeat(2, 1fr);
            }
            .ring-container {
                width: 72px;
                height: 72px;
            }
            .ring-container svg {
                width: 72px;
                height: 72px;
            }
        }
    </style>
</head>
<body>
    <div class="page">
        {logo_section}

        <div class="header">
            <h1>Live Scraping Dashboard</h1>
            <span class="subtitle"><span class="accent-dot"></span>Real-time progress from Scrappy</span>
        </div>

        <!-- Idle / Finished overlay -->
        <div class="idle-overlay" id="idleOverlay">
            <div class="idle-icon" id="idleIcon">&#9203;</div>
            <h2 id="idleTitle">Waiting for scraping...</h2>
            <p id="idleText">Start a scrape in Scrappy and this dashboard will update automatically.</p>
        </div>

        <!-- Active scraping content -->
        <div id="activeContent" style="display: none;">
            <!-- Progress Ring + Info -->
            <div class="progress-section">
                <div class="ring-container">
                    <svg viewBox="0 0 90 90">
                        <circle class="ring-track" cx="45" cy="45" r="38"></circle>
                        <circle class="ring-progress" id="progressRing" cx="45" cy="45" r="38"
                            stroke-dasharray="238.76"
                            stroke-dashoffset="238.76"></circle>
                    </svg>
                    <div class="ring-label">
                        <span id="ringPct">0</span><span class="pct">%</span>
                    </div>
                </div>
                <div class="progress-info">
                    <h2 id="phaseTitle">Initializing...</h2>
                    <div class="progress-detail" id="phaseDetail">Preparing...</div>
                    <div class="progress-detail" id="phaseSubDetail"></div>
                    <div class="progress-bar-bg">
                        <div class="progress-bar-fill" id="progressBar"></div>
                    </div>
                </div>
            </div>

            <!-- Stats Row -->
            <div class="stats-row">
                <div class="stat-card">
                    <div class="stat-value" id="statTotal">0</div>
                    <div class="stat-label">Total</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="statDone" style="color: {success_text}">0</div>
                    <div class="stat-label">Done</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="statFailed" style="color: {failed_text}">0</div>
                    <div class="stat-label">Failed</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="statPhase">&#8212;</div>
                    <div class="stat-label">Phase</div>
                </div>
            </div>

            <!-- Current Game -->
            <div class="current-card">
                <div class="card-title">Currently Processing</div>
                <div class="current-item">
                    <div class="current-icon">&#127918;</div>
                    <div class="current-text">
                        <div class="label">Platform</div>
                        <div class="value" id="curPlatform">N/A</div>
                    </div>
                </div>
                <div class="current-item">
                    <div class="current-icon">&#128191;</div>
                    <div class="current-text">
                        <div class="label">Game</div>
                        <div class="value game-value" id="curGame">N/A</div>
                    </div>
                </div>
                <div class="current-item">
                    <div class="current-icon">&#127760;</div>
                    <div class="current-text">
                        <div class="label">Source</div>
                        <div class="value" id="curSource">N/A</div>
                    </div>
                </div>
            </div>

            <!-- Live Log -->
            <div class="log-section">
                <div class="log-header">
                    <span class="card-title">Live Log</span>
                    <span class="log-count" id="logCount">0 lines</span>
                </div>
                <div class="log-box" id="logBox"></div>
            </div>

            <!-- Failed Games -->
            <div class="failed-section" id="failedSection">
                <div class="failed-header" id="failedHeader">Failed Games (0)</div>
                <ul class="failed-list" id="failedList"></ul>
            </div>
        </div>

        <div class="footer">Scrappy &bull; muOS Artwork Scraper</div>
    </div>

    <script>
        const CIRCUMFERENCE = 2 * Math.PI * 38;
        let lastGame = '';
        let lastPhase = '';
        let eventSource = null;
        let reconnectTimer = null;

        // Theme definitions (same as Python side for consistency)
        const themes = {
            "dark": {
                "bg": "#0a0a0f",
                "card-bg": "#16161e",
                "card-border": "#2a2a35",
                "text-primary": "#e4e4e8",
                "text-secondary": "#9a9aa8",
                "text-muted": "#6a6a78",
                "log-bg": "#0e0e16",
                "log-border": "#2a2a35",
                "stat-bg": "#1a1a24",
                "stat-border": "#2a2a35",
                "phase-fetch-bg": "#0f1a2a",
                "phase-fetch-border": "#1a3a5a",
                "phase-gen-bg": "#0f2a1a",
                "phase-gen-border": "#1a5a3a",
                "failed-bg": "#1a0f0f",
                "failed-border": "#3a1a1a",
                "failed-text": "#e85555",
                "success-text": "#4ade80",
                "logo-filter": "none",
                "ring-track": "#2a2a35",
                "overlay-bg": "rgba(0,0,0,0.6)"
            },
            "light": {
                "bg": "#f0f0f4",
                "card-bg": "#ffffff",
                "card-border": "#e0e0e5",
                "text-primary": "#1a1a2e",
                "text-secondary": "#6a6a7a",
                "text-muted": "#9a9aa8",
                "log-bg": "#f5f5f8",
                "log-border": "#e0e0e5",
                "stat-bg": "#f8f8fc",
                "stat-border": "#e8e8ed",
                "phase-fetch-bg": "#f0f5ff",
                "phase-fetch-border": "#c0d5f0",
                "phase-gen-bg": "#f0fff5",
                "phase-gen-border": "#c0f0d0",
                "failed-bg": "#fff5f5",
                "failed-border": "#f0c0c0",
                "failed-text": "#c02020",
                "success-text": "#22872d",
                "logo-filter": "invert(1)",
                "ring-track": "#e0e0e5",
                "overlay-bg": "rgba(255,255,255,0.6)"
            }
        };

        function updateThemeColors(themeName, accentColor) {
            const root = document.documentElement;
            const t = themes[themeName] || themes["dark"];
            
            for (const [key, value] of Object.entries(t)) {
                root.style.setProperty('--' + key, value);
            }
            if (accentColor) {
                root.style.setProperty('--accent', '#' + accentColor.replace('#', ''));
            }
        }

        function connectSSE() {
            if (eventSource) {
                eventSource.close();
            }
            eventSource = new EventSource('/events');

            eventSource.onmessage = function(e) {
                try {
                    const data = JSON.parse(e.data);
                    
                    // Live theme update
                    if (data.theme || data.accent) {
                        updateThemeColors(data.theme, data.accent);
                    }
                    
                    updateDashboard(data);
                } catch(err) {
                    console.error('Parse error:', err);
                }
            };

            eventSource.onerror = function() {
                eventSource.close();
                // Reconnect after 2 seconds
                if (reconnectTimer) clearTimeout(reconnectTimer);
                reconnectTimer = setTimeout(connectSSE, 2000);
            };
        }

        function classifyLog(line) {
            if (!line) return '';
            if (line.indexOf('found!') !== -1) return 'found';
            if (line.indexOf('ERROR') !== -1 || line.indexOf('not found') !== -1 || line.indexOf('match too low') !== -1) return 'error';
            if (line.indexOf('Starting') !== -1 || line.indexOf('Fetching') !== -1 || line.indexOf('[fetch]') !== -1) return 'info';
            return '';
        }

        function updateDashboard(d) {
            const active = document.getElementById('activeContent');
            const idle = document.getElementById('idleOverlay');

            if (!d.scraping) {
                active.style.display = 'none';
                idle.classList.add('visible');
                if (d.finished) {
                    document.getElementById('idleIcon').innerHTML = '&#10003;';
                    document.getElementById('idleTitle').textContent = 'Scraping Complete!';
                    const total = d.gen_total || 0;
                    const failed = (d.failed || []).length;
                    document.getElementById('idleText').textContent =
                        'Scraped ' + total + ' games, ' + failed + ' failed.';
                } else {
                    document.getElementById('idleIcon').innerHTML = '&#9203;';
                    document.getElementById('idleTitle').textContent = 'Waiting for scraping...';
                    document.getElementById('idleText').textContent = 'Start a scrape in Scrappy and this dashboard will update automatically.';
                }
                return;
            }

            active.style.display = 'block';
            idle.classList.remove('visible');

            // Phase
            const isFetch = d.phase === 'fetch';
            const phaseTitle = document.getElementById('phaseTitle');
            const phaseDetail = document.getElementById('phaseDetail');
            const phaseSubDetail = document.getElementById('phaseSubDetail');
            const statPhase = document.getElementById('statPhase');

            if (isFetch) {
                phaseTitle.textContent = 'Fetching Metadata';
                phaseDetail.textContent = d.fetch_progress ? ('Progress: ' + d.fetch_progress) : 'Downloading game data...';
                phaseSubDetail.textContent = d.pending_platforms ? (d.pending_platforms + ' platform(s) remaining') : '';
                statPhase.textContent = 'Fetch';
                statPhase.title = 'Fetching';
            } else {
                phaseTitle.textContent = 'Generating Artwork';
                const done = d.gen_done || 0;
                const total = d.gen_total || 0;
                phaseDetail.textContent = 'Progress: ' + done + ' / ' + total;
                phaseSubDetail.textContent = '';
                statPhase.textContent = 'Gen';
                statPhase.title = 'Generating';
            }

            // Progress ring
            const total = d.gen_total || 1;
            const done = d.gen_done || 0;
            const pct = Math.min(100, Math.round((done / total) * 100));
            const offset = CIRCUMFERENCE - (pct / 100) * CIRCUMFERENCE;
            document.getElementById('progressRing').style.strokeDashoffset = offset;
            document.getElementById('ringPct').textContent = pct;
            document.getElementById('progressBar').style.width = pct + '%';

            // Stats
            document.getElementById('statTotal').textContent = d.gen_total || 0;
            document.getElementById('statDone').textContent = done;
            document.getElementById('statFailed').textContent = (d.failed || []).length;

            // Current game
            const curPlatform = document.getElementById('curPlatform');
            const curGame = document.getElementById('curGame');
            const curSource = document.getElementById('curSource');

            curPlatform.textContent = d.platform || 'N/A';
            curSource.textContent = d.source || 'N/A';

            // Animate game name change
            if (d.game && d.game !== lastGame) {
                curGame.textContent = d.game;
                curGame.style.animation = 'none';
                curGame.offsetHeight; // trigger reflow
                curGame.style.animation = 'slideIn 0.3s ease-out';
                lastGame = d.game;
            }

            // Logs
            const logBox = document.getElementById('logBox');
            const logs = d.logs || [];
            document.getElementById('logCount').textContent = logs.length + ' lines';

            // Rebuild log content
            let logHtml = '';
            for (let i = 0; i < logs.length; i++) {
                const cls = classifyLog(logs[i]);
                logHtml += '<div class="log-line' + (cls ? ' ' + cls : '') + '">' + escapeHtml(logs[i]) + '</div>';
            }
            logBox.innerHTML = logHtml;
            // Auto-scroll to bottom
            logBox.scrollTop = logBox.scrollHeight;

            // Failed games
            const failedSection = document.getElementById('failedSection');
            const failedList = document.getElementById('failedList');
            const failed = d.failed || [];
            if (failed.length > 0) {
                failedSection.classList.add('visible');
                document.getElementById('failedHeader').textContent = 'Failed Games (' + failed.length + ')';
                let fHtml = '';
                for (let i = 0; i < failed.length; i++) {
                    fHtml += '<li>' + escapeHtml(failed[i]) + '</li>';
                }
                failedList.innerHTML = fHtml;
            } else {
                failedSection.classList.remove('visible');
            }
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // Start SSE connection
        connectSSE();
    </script>
</body>
</html>"""
    html = template.replace("{logo_b64}", logo_b64)
    html = html.replace("{logo_section}", logo_section)
    html = html.replace("{success_text}", t["success_text"])
    html = html.replace("{failed_text}", t["failed_text"])
    html = html.replace("<style>", "<style>\n" + css_vars)
    return html


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler for the scraping dashboard."""

    html_page = ""
    last_state = {}
    lock = threading.Lock()

    def log_message(self, format, *args):
        pass  # Suppress request logging

    def do_GET(self):
        if self.path == '/events':
            self.handle_sse()
        else:
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.end_headers()
            self.wfile.write(DashboardHandler.html_page.encode("utf-8"))

    def handle_sse(self):
        """Server-Sent Events endpoint — streams state updates."""
        self.send_response(200)
        self.send_header("Content-type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        last_json = ""
        try:
            while True:
                state = read_state_file()
                
                # Ensure theme/accent from command line are the default if not in state
                # This allows live updates if Scrappy starts writing them to the JSON
                if "theme" not in state:
                    state["theme"] = getattr(self.server, 'dashboard_theme', 'dark')
                if "accent" not in state:
                    state["accent"] = getattr(self.server, 'dashboard_accent', 'cbaa0f')

                state_json = json.dumps(state, separators=(',', ':'))

                # Only send if state changed
                if state_json != last_json:
                    self.wfile.write(f"data: {state_json}\n\n".encode("utf-8"))
                    self.wfile.flush()
                    last_json = state_json

                    # Check for shutdown signal
                    if state.get("shutdown"):
                        time.sleep(0.5)
                        threading.Thread(target=self.server.shutdown).start()
                        return

                time.sleep(0.5)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # Client disconnected


def read_state_file():
    """Read the scraping state from the temp JSON file."""
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE, "r") as f:
                content = f.read().strip()
                if content:
                    return json.loads(content)
    except (json.JSONDecodeError, IOError):
        pass
    return {"scraping": False}


def main():
    parser = argparse.ArgumentParser(description="Scrappy Live Scraping Dashboard")
    parser.add_argument("--theme", default="dark")
    parser.add_argument("--accent", default="cbaa0f")
    parser.add_argument("--logo", default="")
    args = parser.parse_args()

    # Load and encode logo
    logo_b64 = ""
    if args.logo and os.path.isfile(args.logo):
        try:
            with open(args.logo, "rb") as f:
                logo_b64 = base64.b64encode(f.read()).decode("ascii")
        except Exception:
            pass

    DashboardHandler.html_page = build_html(theme=args.theme, accent=args.accent, logo_b64=logo_b64)

    try:
        # ThreadingTCPServer: each connection gets its own thread
        # Critical for SSE — the long-poll would block all other requests on a single-threaded server
        socketserver.ThreadingTCPServer.allow_reuse_address = True
        socketserver.ThreadingTCPServer.daemon_threads = True
        with socketserver.ThreadingTCPServer(("", PORT), DashboardHandler) as server:
            # Store theme/accent on the server instance so the handler can access them
            server.dashboard_theme = args.theme
            server.dashboard_accent = args.accent
            print(f"Dashboard serving on port {PORT}...", flush=True)
            server.serve_forever()

    except OSError as e:
        print(f"Error starting dashboard server: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nDashboard stopped.", flush=True)
        sys.exit(0)


if __name__ == "__main__":
    main()
