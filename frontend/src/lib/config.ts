/**
 * ============================================================================
 * Prométhée — Assistant IA avancé
 * ============================================================================
 * Auteur  : Pierre COUGET ktulu.analog@gmail.com
 * Licence : GNU Affero General Public License v3.0 (AGPL-3.0)
 *           https://www.gnu.org/licenses/agpl-3.0.html
 * Année   : 2026
 * ----------------------------------------------------------------------------
 * Ce fichier fait partie du projet Prométhée.
 * Vous pouvez le redistribuer et/ou le modifier selon les termes de la
 * licence AGPL-3.0 publiée par la Free Software Foundation.
 * ============================================================================
 *
 *
 * config.ts — Origines HTTP et WebSocket du serveur
 *
 * En production, FastAPI sert la SPA compilée : server/main.py monte
 * frontend/dist sur "/". Front et back partagent donc la même origine, et
 * API_BASE vaut "" — les requêtes sont relatives et suivent le domaine sur
 * lequel l'application est déployée, sans reconstruire l'image.
 *
 * WS_BASE est dérivé de window.location afin de choisir wss:// derrière TLS :
 * un ws:// appelé depuis une page https:// est bloqué par le navigateur
 * (mixed content).
 *
 * Les deux restent surchargeables par VITE_API_URL / VITE_WS_URL pour les
 * déploiements où le front est servi séparément. En développement, c'est
 * frontend/.env.development qui les pointe vers FastAPI sur le port 8000.
 */

function defaultWsBase(): string {
  if (typeof window === "undefined") return "";
  const scheme = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${scheme}//${window.location.host}`;
}

export const API_BASE: string =
  (import.meta as any).env?.VITE_API_URL ?? "";

export const WS_BASE: string =
  (import.meta as any).env?.VITE_WS_URL ?? defaultWsBase();
