/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Coins - Symbols to watch; use | to keep later symbols in the dropdown only */
  "coins": string,
  /** Menu Bar Symbols - Keep symbols visible in the dropdown */
  "hideMenuBarSymbols": boolean,
  /** Currency Symbol - Show prices without $ in the menu bar and dropdown */
  "hideCurrencySymbol": boolean,
  /** Preferred Source - Preferred source; Beacon falls back to the other source when needed */
  "source": "Bybit" | "Binance",
  /** Alert Rules - Looping percent alerts. Format: SYMBOL:PERCENT, for example BTC:1 means alert every 1% move from the last alert price. */
  "alertRules": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `menu-bar` command */
  export type MenuBar = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `menu-bar` command */
  export type MenuBar = {}
}

