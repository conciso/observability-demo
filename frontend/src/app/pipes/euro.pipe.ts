import { Pipe, PipeTransform, inject } from '@angular/core';
import { TranslationService } from '../i18n/translation.service';

/**
 * Formatiert einen Cent-Integer (z.B. 349) als Euro-Betrag in der aktuellen
 * UI-Sprache: "3,49 €" (de-DE) bzw. "€3.49" (en-US).
 */
@Pipe({ name: 'euro', pure: false })
export class EuroPipe implements PipeTransform {
  private readonly i18n = inject(TranslationService);
  private static readonly formatters = new Map<string, Intl.NumberFormat>();

  transform(cents: number | null | undefined): string {
    const value = (cents ?? 0) / 100;
    return EuroPipe.formatter(this.i18n.locale()).format(value);
  }

  private static formatter(locale: string): Intl.NumberFormat {
    let formatter = EuroPipe.formatters.get(locale);
    if (!formatter) {
      formatter = new Intl.NumberFormat(locale, { style: 'currency', currency: 'EUR' });
      EuroPipe.formatters.set(locale, formatter);
    }
    return formatter;
  }
}
