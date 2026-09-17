import { Pipe, PipeTransform } from '@angular/core';

/**
 * Formatiert einen Cent-Integer (z.B. 349) als Euro-Betrag ("3,49 EUR").
 * Nutzt Intl.NumberFormat mit de-DE-Locale.
 */
@Pipe({ name: 'euro' })
export class EuroPipe implements PipeTransform {
  private static readonly formatter = new Intl.NumberFormat('de-DE', {
    style: 'currency',
    currency: 'EUR',
  });

  transform(cents: number | null | undefined): string {
    const value = (cents ?? 0) / 100;
    return EuroPipe.formatter.format(value);
  }
}
