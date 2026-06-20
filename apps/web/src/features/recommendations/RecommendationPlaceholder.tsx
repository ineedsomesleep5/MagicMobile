import type { Recommendation } from "@magicmobile/shared";

interface RecommendationPlaceholderProps {
  recommendations?: Recommendation[];
  edhrecCommanderUrl?: string | undefined;
}

export function RecommendationPlaceholder({
  recommendations = [],
  edhrecCommanderUrl
}: RecommendationPlaceholderProps) {
  return (
    <section aria-labelledby="recommendations-heading">
      <div>
        <h2 id="recommendations-heading">Recommendations</h2>
        {edhrecCommanderUrl ? (
          <a href={edhrecCommanderUrl} rel="noreferrer" target="_blank">
            Open commander page on EDHREC
          </a>
        ) : null}
      </div>

      {recommendations.length > 0 ? (
        <ul>
          {recommendations.map((recommendation) => (
            <li key={`${recommendation.source}-${recommendation.cardName}`}>
              <strong>{recommendation.cardName}</strong>
              <span>{recommendation.reason}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p>Local recommendations are not available yet.</p>
      )}
    </section>
  );
}
