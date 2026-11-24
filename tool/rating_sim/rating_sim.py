"""Simulation: Welches Wertungssystem passt zum Schieber?

Vergleicht vier Verfahren auf künstlichen Spielerinnen und Spielern mit
bekannter «wahrer» Spielstärke:

  1. Klassisches Elo   (nur Sieg/Niederlage, Team = Mittelwert)
  2. Differenz-Elo     (Formel des Jassverbands: Strichdifferenz, S=1000, K=32, Start 100)
  3. TrueSkill         (Bayes, nur Sieg/Niederlage, mit Unsicherheit sigma)
  4. Striche-Bayes     (TrueSkill-artig mit Unsicherheit, lernt aber aus der Strichdifferenz;
                        unser Vorschlag, intern «Jass-Rating»)

Modell eines Schiebers (Annahme, bewusst einfach):
  - jede Person hat eine wahre Stärke theta ~ N(0, 0.5)
  - Leistung Team A minus Team B = (Summe theta A - Summe theta B) + Glück
  - Glück ~ N(0, L); L = 1 (wenig), 2 (normal), 3 (viel Glück)
  - Sieg, wenn Differenz > 0; Strichdifferenz = gerundet 2*Differenz, begrenzt auf -7..7
    (mindestens 1 Strich für das Siegerteam)
  - wahre Stärke wandert leicht (Lernen/Formschwankung): +N(0, 0.01) pro Partie

Szenarien:
  - random:   4 zufällige Personen pro Tisch (Ranked Solo, wechselnde Partner)
  - carry:    wie random, aber 10 % schwache Personen spielen immer mit einer der
              10 % stärksten (Trittbrett-Test: wird die schwache Person überbewertet?)
  - match:    Matchmaking: 75 % der Tische mit vier etwa gleich starken Personen
              (aus den 10 % Nächsten), 25 % zufällig gemischt
  - duo:      feste Zweierteams gegen andere feste Zweierteams
  - duplicate: wie random, aber Kartenglück zu 70 % herausgerechnet (Duplicate Jass)

Gemessen:
  - rho_N:    Rangkorrelation (Spearman) zwischen Wertung und wahrer Stärke,
              nachdem jede Person im Schnitt N Partien gespielt hat (1 = perfekt)
  - games80:  Partien pro Person, bis rho >= 0.8 erreicht ist
  - acc:      Trefferquote der Siegprognose für die nächste Partie (letztes Viertel)
  - logloss:  Güte der Wahrscheinlichkeitsprognose (tiefer = besser)
  - carry_bias: wie stark die Wertung der «Mitfahrer» über ihrer wahren Stärke liegt
              (in Standardabweichungen der Wertung, 0 = fair)
  - duo_split: Rangkorrelation innerhalb der festen Duos (kann man stärkere und schwächere
              Hälfte unterscheiden?)

Aufruf:  python3 tool/rating_sim/rating_sim.py  [--seeds 5]
Nur Python 3 + numpy nötig.
"""

import argparse
import math
import numpy as np

SQRT2 = math.sqrt(2.0)


def phi(x):
    return math.exp(-0.5 * x * x) / math.sqrt(2 * math.pi)


def Phi(x):
    return 0.5 * (1.0 + math.erf(x / SQRT2))


def spearman(a, b):
    ra = np.argsort(np.argsort(a))
    rb = np.argsort(np.argsort(b))
    return float(np.corrcoef(ra, rb)[0, 1])


# ---------------------------------------------------------------- Verfahren

class ClassicElo:
    name = "Klassisches Elo"

    def __init__(self, n):
        self.r = np.full(n, 1500.0)
        self.k = 32.0

    def p_win(self, a, b):
        ra = (self.r[a[0]] + self.r[a[1]]) / 2
        rb = (self.r[b[0]] + self.r[b[1]]) / 2
        return 1.0 / (1.0 + 10 ** ((rb - ra) / 400.0))

    def update(self, a, b, win, margin):
        e = self.p_win(a, b)
        d = self.k * ((1.0 if win else 0.0) - e)
        for i in a:
            self.r[i] += d
        for i in b:
            self.r[i] -= d

    def rating(self):
        return self.r


class DiffElo:
    """Formel gemäss jassverband.ch/de/research/jass-elo (Stand Sept. 2025)."""

    def __init__(self, n, scale=1000.0, k=32.0, start=100.0, name="Differenz-Elo (Jassverband)"):
        self.r = np.full(n, start)
        self.s = scale
        self.k = k
        self.name = name

    def p_win(self, a, b):
        ra = (self.r[a[0]] + self.r[a[1]]) / 2
        rb = (self.r[b[0]] + self.r[b[1]]) / 2
        return 1.0 / (1.0 + 10 ** ((rb - ra) / self.s))

    def update(self, a, b, win, margin):
        ea = self.p_win(a, b)
        total = 7.0  # «TotalStriche» ist auf der Seite nicht definiert; wir nehmen maxDiff
        expected = (2 * ea - 1) * total
        sa = max(0.0, min(1.0, 0.5 + (margin - expected) / 14.0))
        d_team = self.k * (sa - ea)
        for i in a:
            self.r[i] += d_team / 2
        for i in b:
            self.r[i] -= d_team / 2

    def rating(self):
        return self.r


class TrueSkill:
    """Zwei Teams, keine Unentschieden, Teamstärke = Summe (wie TrueSkill)."""

    name = "TrueSkill"

    def __init__(self, n, beta=None, tau=None):
        self.mu = np.full(n, 25.0)
        self.var = np.full(n, (25.0 / 3) ** 2)
        self.beta2 = (beta or 25.0 / 6) ** 2
        self.tau2 = (tau or 25.0 / 300) ** 2

    def _c(self, a, b):
        return math.sqrt(sum(self.var[i] for i in a + b) + 4 * self.beta2)

    def p_win(self, a, b):
        d = sum(self.mu[i] for i in a) - sum(self.mu[i] for i in b)
        return Phi(d / self._c(a, b))

    def update(self, a, b, win, margin):
        for i in a + b:
            self.var[i] += self.tau2
        w_team, l_team = (a, b) if win else (b, a)
        c = self._c(a, b)
        t = (sum(self.mu[i] for i in w_team) - sum(self.mu[i] for i in l_team)) / c
        v = phi(t) / max(Phi(t), 1e-12)
        w = v * (v + t)
        for i in w_team:
            self.mu[i] += self.var[i] / c * v
            self.var[i] *= max(1 - self.var[i] / c ** 2 * w, 1e-4)
        for i in l_team:
            self.mu[i] -= self.var[i] / c * v
            self.var[i] *= max(1 - self.var[i] / c ** 2 * w, 1e-4)

    def rating(self):
        return self.mu  # für die Rangliste zählt der Mittelwert (sichtbare Wertung: mu - 2*sigma)


class StricheBayes:
    """Unser Vorschlag: Gauss-Modell auf der Strichdifferenz (Kalman-Update).

    Strichdifferenz m ~ N(g * (Summe mu A - Summe mu B), noise^2).
    Jede Person hat Mittelwert mu und Unsicherheit var; var wächst leicht mit der Zeit.
    """

    name = "Striche-Bayes (Vorschlag)"

    def __init__(self, n, noise=None, g=2.0, prior_sd=0.5, drift=0.01):
        self.mu = np.zeros(n)
        self.var = np.full(n, prior_sd ** 2)
        self.g = g
        self.noise2 = (noise if noise is not None else 4.0) ** 2
        self.drift2 = drift ** 2

    def p_win(self, a, b):
        d = sum(self.mu[i] for i in a) - sum(self.mu[i] for i in b)
        s2 = sum(self.var[i] for i in a + b) * self.g ** 2 + self.noise2
        return Phi(self.g * d / math.sqrt(s2))

    def update(self, a, b, win, margin):
        for i in a + b:
            self.var[i] += self.drift2
        pred = self.g * (sum(self.mu[i] for i in a) - sum(self.mu[i] for i in b))
        s2 = sum(self.var[i] for i in a + b) * self.g ** 2 + self.noise2
        resid = margin - pred
        for sign, team in ((1, a), (-1, b)):
            for i in team:
                gain = sign * self.g * self.var[i] / s2
                self.mu[i] += gain * resid
                self.var[i] -= (self.g * self.var[i]) ** 2 / s2

    def rating(self):
        return self.mu


# ---------------------------------------------------------------- Welt

def play(theta, a, b, luck, rng, dup=False):
    skill = theta[a[0]] + theta[a[1]] - theta[b[0]] - theta[b[1]]
    noise = rng.normal(0, luck)
    if dup:
        noise *= math.sqrt(0.3)  # 70 % der Glücksvarianz (Kartenverteilung) fällt weg
    d = skill + noise
    win = d > 0
    m = int(round(2 * d))
    m = max(-7, min(7, m))
    if win and m < 1:
        m = 1
    if not win and m > -1:
        m = -1
    return win, m


def make_systems(n, luck):
    return [
        ClassicElo(n),
        DiffElo(n),
        TrueSkill(n),
        StricheBayes(n, noise=4.0),  # fest, NICHT an das wahre Glück angepasst
    ]


def run(scenario, luck, seed, n=400, games_per_player=200, checkpoints=(10, 20, 50, 100, 200)):
    rng = np.random.default_rng(seed)
    theta = rng.normal(0, 0.5, n)
    systems = make_systems(n, luck)
    total_games = games_per_player * n // 4
    played = 0
    res = {s.name: {"rho": {}, "hits": 0, "ll": 0.0, "cnt": 0, "g80": None} for s in systems}

    # Trittbrett-Szenario: schwächste 10 % immer mit einer der stärksten 10 %
    order = np.argsort(theta)
    weak = list(order[: n // 10])
    strong = list(order[-n // 10:])
    others = [i for i in range(n) if i not in set(weak) | set(strong)]

    # Duo-Szenario: feste Paare
    perm = rng.permutation(n)
    duos = [(int(perm[2 * i]), int(perm[2 * i + 1])) for i in range(n // 2)]

    cps = list(checkpoints)
    step_check = sorted(set([5 * k for k in range(1, games_per_player // 5 + 1)]))
    for g in range(total_games):
        if scenario == "duo":
            i, j = rng.choice(len(duos), 2, replace=False)
            a, b = list(duos[i]), list(duos[j])
        elif scenario == "carry" and rng.random() < 0.2:
            k = int(rng.integers(len(weak)))
            a = [int(weak[k]), int(strong[k])]
            b = [int(x) for x in rng.choice(others, 2, replace=False)]
        elif scenario == "match" and rng.random() < 0.75:
            # Matchmaking: vier Personen mit ähnlicher (wahrer) Stärke an einen Tisch
            c = int(rng.integers(n))
            pool = np.argsort(np.abs(theta - theta[c]))[:40]
            p = rng.choice(pool, 4, replace=False)
            a, b = [int(p[0]), int(p[1])], [int(p[2]), int(p[3])]
        else:
            p = rng.choice(n, 4, replace=False)
            a, b = [int(p[0]), int(p[1])], [int(p[2]), int(p[3])]
        win, m = play(theta, a, b, luck, rng, dup=(scenario == "duplicate"))
        last_quarter = g >= total_games * 3 // 4
        for s in systems:
            if last_quarter:
                p = min(max(s.p_win(a, b), 1e-6), 1 - 1e-6)
                r = res[s.name]
                r["hits"] += int((p > 0.5) == win)
                r["ll"] += -math.log(p if win else 1 - p)
                r["cnt"] += 1
            s.update(a, b, win, m)
        theta = theta + rng.normal(0, 0.01 * 4 / n, n)  # sanfte Drift (~0.01 pro gespielter Partie)
        played += 4
        gpp = played / n
        if abs(gpp - round(gpp)) < 1e-9 and int(round(gpp)) in step_check:
            gp = int(round(gpp))
            for s in systems:
                rho = spearman(s.rating(), theta)
                r = res[s.name]
                if gp in cps:
                    r["rho"][gp] = rho
                if r["g80"] is None and rho >= 0.8:
                    r["g80"] = gp

    for s in systems:
        r = res[s.name]
        r["acc"] = r["hits"] / max(r["cnt"], 1)
        r["logloss"] = r["ll"] / max(r["cnt"], 1)
        rating = np.asarray(s.rating(), dtype=float)
        z = (rating - rating.mean()) / (rating.std() + 1e-12)
        zt = (theta - theta.mean()) / theta.std()
        r["carry_bias"] = float(np.mean(z[weak] - zt[weak])) if scenario == "carry" else None
        if scenario == "duo":
            same = [(1 if (rating[x] - rating[y]) * (theta[x] - theta[y]) > 0 else 0) for x, y in duos]
            r["duo_split"] = sum(same) / len(same)
        else:
            r["duo_split"] = None
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=3)
    args = ap.parse_args()
    scenarios = [("random", 1.0), ("random", 2.0), ("random", 3.0),
                 ("match", 2.0), ("carry", 2.0), ("duo", 2.0), ("duplicate", 2.0)]
    for scen, luck in scenarios:
        agg = {}
        for seed in range(args.seeds):
            res = run(scen, luck, seed)
            for name, r in res.items():
                a = agg.setdefault(name, {"rho": {}, "acc": [], "ll": [], "g80": [], "carry": [], "duo": []})
                for k, v in r["rho"].items():
                    a["rho"].setdefault(k, []).append(v)
                a["acc"].append(r["acc"])
                a["ll"].append(r["logloss"])
                a["g80"].append(r["g80"] if r["g80"] is not None else 999)
                if r["carry_bias"] is not None:
                    a["carry"].append(r["carry_bias"])
                if r["duo_split"] is not None:
                    a["duo"].append(r["duo_split"])
        print(f"\n=== Szenario {scen}, Glück L={luck} ===")
        print(f"{'Verfahren':34s} rho10 rho20 rho50 rho100 rho200  g80   acc   logloss  carry  duo")
        for name, a in agg.items():
            rho = " ".join(f"{np.mean(a['rho'].get(k, [float('nan')])):5.2f}" for k in (10, 20, 50, 100, 200))
            g80 = np.median(a["g80"])
            g80s = ">200" if g80 >= 999 else f"{g80:4.0f}"
            carry = f"{np.mean(a['carry']):+.2f}" if a["carry"] else "   - "
            duo = f"{np.mean(a['duo']):.2f}" if a["duo"] else "  - "
            print(f"{name:34s} {rho}  {g80s:>4s}  {np.mean(a['acc']):.3f}  {np.mean(a['ll']):.3f}  {carry}  {duo}")


if __name__ == "__main__":
    main()
