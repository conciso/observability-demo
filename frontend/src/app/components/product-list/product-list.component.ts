import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { Product } from '../../models/models';
import { EuroPipe } from '../../pipes/euro.pipe';

/**
 * Praesentationskomponente: zeigt den Produktkatalog als Karten an
 * und meldet ueber `add`, wenn ein Produkt in den Warenkorb soll.
 */
@Component({
  selector: 'app-product-list',
  standalone: true,
  imports: [EuroPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './product-list.component.html',
  styleUrl: './product-list.component.css',
})
export class ProductListComponent {
  readonly products = input.required<Product[]>();
  readonly add = output<Product>();
}
