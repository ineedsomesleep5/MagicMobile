import { Button } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";

export default function SettingsPage() {
  return (
    <>
      <PageHeader title="Settings" kicker="Local preferences" />
      <form className="form-panel">
        <h2>Player profile</h2>
        <label className="field">
          Display name
          <input defaultValue="Commander Player" />
        </label>
        <label className="field">
          Preferred seat mode
          <select defaultValue="hybrid">
            <option value="digital">Digital</option>
            <option value="webcam">Webcam</option>
            <option value="hybrid">Hybrid</option>
          </select>
        </label>
        <Button tone="primary">Save Local Settings</Button>
      </form>
    </>
  );
}
