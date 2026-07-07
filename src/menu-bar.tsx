import { MenuBarExtra, openCommandPreferences } from "@raycast/api";

export default function Command() {
  return (
    <MenuBarExtra title="Beacon">
      <MenuBarExtra.Section>
        <MenuBarExtra.Item title="Settings" onAction={openCommandPreferences} shortcut={{ key: ",", modifiers: ["cmd"] }} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
