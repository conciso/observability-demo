import { ChangeDetectionStrategy, Component, inject, input, output } from '@angular/core';
import { Product } from '../../models/models';
import { EuroPipe } from '../../pipes/euro.pipe';
import { TranslationService } from '../../i18n/translation.service';
import { CatalogPipe } from '../../i18n/catalog.pipe';

/**
 * Praesentationskomponente: zeigt den Produktkatalog als Karten an
 * und meldet ueber `add`, wenn ein Produkt in den Warenkorb soll.
 */
@Component({
  selector: 'app-product-list',
  imports: [EuroPipe, CatalogPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './product-list.component.html',
  styleUrl: './product-list.component.css',
})
export class ProductListComponent {
  protected readonly i18n = inject(TranslationService);

  readonly products = input.required<Product[]>();
  readonly add = output<Product>();
}
