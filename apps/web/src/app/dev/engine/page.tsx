import { Button } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";

const checks = [
  ["Engine adapter", "Mock adapter renders the Play page"],
  ["Room service", "In-memory API flow supports create, join, ready, start, and get"],
  ["Card data", "Seed provider feeds deck detail stats"],
  ["Recommendation UI", "Mock recommendations render in deck detail"]
];

export default function DevEnginePage() {
  return (
    <>
      <PageHeader title="Engine Dev" kicker="Contract visibility" actions={<Button>Run Mock Advance Phase</Button>} />
      <section className="panel">
        <h2>Milestone boundaries</h2>
        <table className="dev-table">
          <thead>
            <tr>
              <th>Area</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {checks.map(([area, status]) => (
              <tr key={area}>
                <td>{area}</td>
                <td>{status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  );
}
