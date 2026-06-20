import { Button } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";

export default function NewDeckPage() {
  return (
    <>
      <PageHeader title="New Deck" kicker="Paste a Commander list" />
      <form className="form-panel">
        <h2>Deck import placeholder</h2>
        <label className="field">
          Deck name
          <input name="name" placeholder="Rhys Wide Table" />
        </label>
        <label className="field">
          Commander
          <input name="commander" placeholder="Rhys the Redeemed" />
        </label>
        <label className="field">
          Deck list
          <textarea name="decklist" placeholder="1 Command Tower&#10;1 Sol Ring&#10;1 Cultivate" />
        </label>
        <div className="actions">
          <Button tone="primary">Analyze Mock Deck</Button>
          <Button>Save Draft</Button>
        </div>
      </form>
    </>
  );
}
