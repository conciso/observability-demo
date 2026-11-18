import { Injectable, computed, effect, signal } from '@angular/core';
import { CATALOG_EN_US, Lang, MESSAGES, Messages, SUPPORTED_LANGS, TextKey } from './translations';

/** Schluessel, fuer die es eine Singular-Variante `<key>One` gibt. */
type CountKey = { [K in TextKey]: `${K}One` extends TextKey ? K : never }[TextKey];

const STORAGE_KEY = 'food-order.lang';

/**
 * Signal-basierte Laufzeit-Uebersetzung (Deutsch / amerikanisches Englisch).
 * Die gewaehlte Sprache wird im localStorage gemerkt; ohne Auswahl entscheidet
 * die Browsersprache (en-* -> en-US, sonst Deutsch).
 */
@Injectable({ providedIn: 'root' })
export class TranslationService {
  readonly lang = signal<Lang>(TranslationService.initialLang());

  /** Aktuelle Texte; Templates lesen z.B. `i18n.messages().cart`. */
  readonly messages = computed<Messages>(() => MESSAGES[this.lang()]);

  /** Locale fuer Intl-Formatierung (Zahlen, Waehrung). */
  readonly locale = computed(() => (this.lang() === 'de' ? 'de-DE' : 'en-US'));

  constructor() {
    effect(() => {
      const lang = this.lang();
      document.documentElement.lang = lang;
      document.title = this.messages().appTitle;
      try {
        localStorage.setItem(STORAGE_KEY, lang);
      } catch {
        // Storage nicht verfuegbar (z.B. privater Modus) -> nur fuer diese Sitzung
      }
    });
  }

  /** Sprache setzen; unbekannte Werte (z.B. aus dem DOM) werden ignoriert. */
  setLang(lang: string): void {
    if (TranslationService.isLang(lang)) {
      this.lang.set(lang);
    }
  }

  /** Text mit Platzhaltern ({name}) befuellen. */
  t(key: TextKey, params: Record<string, string | number> = {}): string {
    return this.messages()[key].replace(/\{(\w+)\}/g, (match, name: string) =>
      name in params ? String(params[name]) : match,
    );
  }

  /** Text mit Mengenangabe: waehlt Singular (`<key>One`) oder Plural anhand der Pluralregeln der Sprache. */
  tCount(key: CountKey, count: number): string {
    const one = new Intl.PluralRules(this.locale()).select(count) === 'one';
    return this.t(one ? `${key}One` : key, { count });
  }

  /** Bestellstatus aus dem Backend uebersetzen; unbekannte Werte unveraendert. */
  orderStatus(status: string): string {
    return (this.messages().orderStatus as Record<string, string>)[status] ?? status;
  }

  /** Katalogtext (Produktname, Beschreibung, Kategorie) aus dem Backend uebersetzen. */
  catalog(text: string): string {
    return this.lang() === 'en-US' ? (CATALOG_EN_US[text] ?? text) : text;
  }

  private static isLang(value: string): value is Lang {
    return (SUPPORTED_LANGS as readonly string[]).includes(value);
  }

  private static initialLang(): Lang {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored && TranslationService.isLang(stored)) {
        return stored;
      }
    } catch {
      // ignorieren, Fallback auf Browsersprache
    }
    return navigator.language?.toLowerCase().startsWith('en') ? 'en-US' : 'de';
  }
}
