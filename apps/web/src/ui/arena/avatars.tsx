/** The two medallion portraits (the prototype's): yours lit in ember, theirs in arcane blue. */
export const AVATAR = {
  me: (
    <svg viewBox="0 0 100 100" aria-hidden="true">
      <defs><radialGradient id="avMe" cx=".5" cy=".75" r=".8"><stop offset="0" stopColor="#ffb36a" /><stop offset=".55" stopColor="#8a2a12" /><stop offset="1" stopColor="#2a0c06" /></radialGradient></defs>
      <rect width="100" height="100" fill="url(#avMe)" /><path d="M50 18c-18 0-28 16-28 34v48h56V52c0-18-10-34-28-34z" fill="#1b0c06" />
      <path d="M50 30c-9 0-15 10-15 21h30c0-11-6-21-15-21z" fill="#2c140a" /><circle cx="44" cy="50" r="2.6" fill="#ffb070" /><circle cx="56" cy="50" r="2.6" fill="#ffb070" />
      <circle cx="50" cy="86" r="5" fill="#ff8a3d" opacity=".8" />
    </svg>
  ),
  opp: (
    <svg viewBox="0 0 100 100" aria-hidden="true">
      <defs><radialGradient id="avOpp" cx=".5" cy=".65" r=".8"><stop offset="0" stopColor="#a8dcff" /><stop offset=".55" stopColor="#2a5a96" /><stop offset="1" stopColor="#0a1830" /></radialGradient></defs>
      <rect width="100" height="100" fill="url(#avOpp)" /><path d="M24 100c2-18 12-26 26-26s24 8 26 26z" fill="#0b1b33" /><circle cx="50" cy="52" r="16" fill="#0b1b33" />
      <path d="M33 38l6 10 11-12 11 12 6-10v12H33z" fill="#dba34c" /><circle cx="44" cy="53" r="2.2" fill="#c8eaff" /><circle cx="56" cy="53" r="2.2" fill="#c8eaff" />
    </svg>
  ),
};
