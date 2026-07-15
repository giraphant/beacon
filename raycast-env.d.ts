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
  /** Preferred Source - Use Relay, or prefer one direct exchange and fall back to the other */
  "source": "Bybit" | "Binance" | "Relay",
  /** Relay URL - HTTPS base URL for the Beacon quote relay */
  "relayUrl"?: string,
  /** Relay Token - Bearer token configured on the Beacon quote relay */
  "relayToken"?: string,
  /** Alert Rules - Looping percent alerts. Format: SYMBOL:PERCENT, for example BTC:1 means alert every 1% move from the last alert price. */
  "alertRules": string,
  /** Integer Alert Rules - Price-level alerts. Format: SYMBOL:STEP, for example BTC:1000 alerts when BTC crosses each $1000 boundary. */
  "integerAlertRules": string,
  /** Integer Alert Cooldown Minutes - Suppress repeated notifications for the same integer boundary per coin and step. Set 0 to disable. */
  "integerAlertCooldownMinutes": string,
  /** Alert Sound - Play a short sound when Beacon shows a price alert HUD and toast */
  "alertSoundEnabled": boolean
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

