import { Pipe, PipeTransform, inject } from '@angular/core';
import { TranslationService } from './translation.service';

/** Uebersetzt Katalogtexte aus dem Backend in die aktuelle UI-Sprache. */
@Pipe({ name: 'catalog', pure: false })
export class CatalogPipe implements PipeTransform {
  private readonly i18n = inject(TranslationService);

  transform(text: string | null | undefined): string {
    return text ? this.i18n.catalog(text) : '';
  }
}
