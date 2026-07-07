/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Coins - Symbols to watch; use | to keep later symbols in the dropdown only */
  "coins": string,
  /** Hide Menu Bar Symbols - Show only prices in the menu bar title while keeping symbols in the dropdown */
  "hideMenuBarSymbols": boolean,
  /** Hide Currency Symbol - Show prices without the currency symbol */
  "hideCurrencySymbol": boolean,
  /** Preferred Source - Source to try first before falling back to the other source */
  "source": "Bybit" | "Binance",
  /** Alert Rules - Recurring alert rules such as BTC:2 NVDA:1.5 SOL:1 */
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

