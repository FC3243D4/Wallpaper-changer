// ==UserScript==
// @name         Zen Theme Hot Reload
// @namespace    userChrome.js
// @description  Watches userChrome.css and userContent.css (as written by zenPatcher.sh) and live-reloads them without restarting.
// @version      1.0
// @include      main
// @onlyonce
// ==/UserScript==
(function () {
  "use strict";
  console.warn("[ZenThemeReloader] SCRIPT EVALUATED");

  const WATCHED_FILES = [
    { name: "userChrome.css", sheetTypes: ["USER_SHEET", "AGENT_SHEET"] },
    { name: "userContent.css", sheetTypes: ["USER_SHEET"] },
  ];

  const sss = Cc["@mozilla.org/content/style-sheet-service;1"].getService(
    Ci.nsIStyleSheetService,
  );

  class Watcher {
    constructor(fileName, sheetTypeNames) {
      this.fileName = fileName;
      this.sheetTypes = sheetTypeNames.map((t) => sss[t]);
      this.file = null;
      this.lastModified = 0;
    }

    init() {
      try {
        const chromeDir = Services.dirsvc.get("UChrm", Ci.nsIFile);
        chromeDir.append(this.fileName);
        this.file = chromeDir;
        if (!this.file.exists() || !this.file.isFile()) {
          console.warn(
            `[ZenThemeReloader] ${this.fileName} NOT FOUND at: ${this.file.path}`,
          );
          return false;
        }
        this.lastModified = this.file.lastModifiedTime;
        console.warn(`[ZenThemeReloader] Watching: ${this.file.path}`);
        return true;
      } catch (e) {
        console.error(`[ZenThemeReloader] Init Error (${this.fileName}): ${e}`);
        return false;
      }
    }

    checkAndReload() {
      try {
        const fresh = this.file.clone();
        if (fresh.exists() && fresh.lastModifiedTime > this.lastModified) {
          this.lastModified = fresh.lastModifiedTime;
          this.reload();
        }
      } catch (e) {
        console.error(`[ZenThemeReloader] Watch Error (${this.fileName}): ${e}`);
      }
    }

    reload() {
      try {
        const uri = Services.io.newFileURI(this.file);
        for (const type of this.sheetTypes) {
          if (sss.sheetRegistered(uri, type)) {
            sss.unregisterSheet(uri, type);
          }
          sss.loadAndRegisterSheet(uri, type);
        }
        Services.obs.notifyObservers(null, "chrome-flush-caches", null);
        console.warn(`[ZenThemeReloader] Reloaded: ${this.fileName}`);
      } catch (e) {
        console.error(`[ZenThemeReloader] Reload Error (${this.fileName}): ${e}`);
      }
    }
  }

  const Reloader = {
    watchers: [],
    timer: null,
    init() {
      console.warn("[ZenThemeReloader] Initializing...");
      this.watchers = WATCHED_FILES.map(
        (f) => new Watcher(f.name, f.sheetTypes),
      ).filter((w) => w.init());
      if (this.watchers.length === 0) {
        console.warn("[ZenThemeReloader] No files found to watch, aborting.");
        return;
      }
      this.start();
    },
    start() {
      if (this.timer) clearInterval(this.timer);
      this.timer = setInterval(() => {
        for (const w of this.watchers) w.checkAndReload();
      }, 1000);
    },
  };

  setTimeout(() => {
    Reloader.init();
  }, 1000);
})();
