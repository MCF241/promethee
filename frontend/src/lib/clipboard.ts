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
 * clipboard.ts — Copie dans le presse-papiers, y compris hors contexte sécurisé
 *
 * `navigator.clipboard` n'est exposé que dans un *contexte sécurisé* : une page
 * servie en HTTPS, ou depuis localhost. Une instance jointe par son nom d'hôte
 * ou son adresse IP en HTTP simple — le cas d'un déploiement en mode serveur
 * sans TLS — n'en dispose donc pas : l'objet vaut `undefined` et tout appel
 * lève une TypeError.
 *
 * Le symptôme est déroutant : l'application fonctionne, mais chaque bouton de
 * copie échoue, sans que rien n'indique pourquoi.
 *
 * On passe donc par un repli fondé sur `document.execCommand("copy")`, qui
 * reste disponible hors contexte sécurisé. Obsolète au sens de la
 * spécification, il demeure implémenté par tous les navigateurs courants et
 * n'a aucune alternative dans ce cas de figure.
 *
 * Le repli couvre le texte et le HTML. Il ne couvre pas les images : aucun
 * mécanisme historique ne permet de déposer un binaire dans le presse-papiers.
 * `copierImage` échoue alors avec un message explicite plutôt qu'avec une
 * TypeError incompréhensible.
 */

/** Le presse-papiers moderne est-il utilisable ? */
export function pressePapiersNatifDisponible(): boolean {
  return typeof navigator !== "undefined" && !!navigator.clipboard;
}

/**
 * Exécute une copie via une sélection temporaire, hors écran.
 * Renvoie `true` si le navigateur a accepté la copie.
 */
function copierParSelection(remplir: (hote: HTMLElement) => void): boolean {
  const hote = document.createElement("div");
  hote.setAttribute("contenteditable", "true");
  // Hors écran mais bien rendu : un élément masqué par `display:none` ou
  // `visibility:hidden` ne peut pas être sélectionné.
  hote.style.position = "fixed";
  hote.style.top = "-9999px";
  hote.style.left = "-9999px";
  hote.style.opacity = "0";
  hote.style.whiteSpace = "pre-wrap";
  remplir(hote);
  document.body.appendChild(hote);

  const selection = window.getSelection();
  const selectionPrecedente =
    selection && selection.rangeCount > 0 ? selection.getRangeAt(0) : null;

  let succes = false;
  try {
    const plage = document.createRange();
    plage.selectNodeContents(hote);
    selection?.removeAllRanges();
    selection?.addRange(plage);
    succes = document.execCommand("copy");
  } catch {
    succes = false;
  } finally {
    selection?.removeAllRanges();
    // Restitue la sélection de l'utilisateur, qu'on vient de lui voler.
    if (selectionPrecedente) selection?.addRange(selectionPrecedente);
    document.body.removeChild(hote);
  }
  return succes;
}

/** Copie du texte brut. Lève une erreur si aucune méthode n'aboutit. */
export async function copierTexte(texte: string): Promise<void> {
  if (pressePapiersNatifDisponible()) {
    try {
      await navigator.clipboard.writeText(texte);
      return;
    } catch {
      // Refus de permission ou document sans focus : on tente le repli.
    }
  }
  if (copierParSelection((hote) => { hote.textContent = texte; })) return;
  throw new Error(messageEchec());
}

/**
 * Copie du HTML mis en forme, pour un collage dans Word, LibreOffice ou Pages.
 * `texteBrut` sert de version dégradée pour les cibles qui n'acceptent que du
 * texte ; à défaut, le texte rendu du HTML est utilisé.
 */
export async function copierHtml(html: string, texteBrut?: string): Promise<void> {
  if (pressePapiersNatifDisponible() && typeof ClipboardItem !== "undefined") {
    try {
      const elements: Record<string, Blob> = {
        "text/html": new Blob([html], { type: "text/html" }),
      };
      if (texteBrut !== undefined) {
        elements["text/plain"] = new Blob([texteBrut], { type: "text/plain" });
      }
      await navigator.clipboard.write([new ClipboardItem(elements)]);
      return;
    } catch {
      // On tente le repli.
    }
  }
  // La sélection d'un contenu réellement rendu préserve la mise en forme au
  // collage, ce qu'un simple texte ne ferait pas.
  if (copierParSelection((hote) => { hote.innerHTML = html; })) return;
  throw new Error(messageEchec());
}

/**
 * Copie une image. Sans presse-papiers moderne, l'opération est impossible :
 * aucun repli n'existe pour un binaire.
 */
export async function copierImage(blob: Blob): Promise<void> {
  if (!pressePapiersNatifDisponible() || typeof ClipboardItem === "undefined") {
    throw new Error(
      "La copie d'image exige une connexion sécurisée (HTTPS). " +
        "Utilisez le téléchargement, ou servez l'application derrière un reverse proxy TLS."
    );
  }
  await navigator.clipboard.write([new ClipboardItem({ [blob.type]: blob })]);
}

function messageEchec(): string {
  return pressePapiersNatifDisponible()
    ? "La copie a été refusée par le navigateur."
    : "Copie impossible : cette page n'est pas servie en HTTPS, et le navigateur " +
        "a refusé la méthode de repli. Servez l'application derrière un reverse proxy TLS.";
}
