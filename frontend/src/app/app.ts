import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { ProductListComponent } from './components/product-list/product-list.component';
import { CartComponent } from './components/cart/cart.component';
import { OrderConfirmationComponent } from './components/order-confirmation/order-confirmation.component';
import { ProductService } from './services/product.service';
import { OrderService } from './services/order.service';
import { CartService } from './services/cart.service';
import { TranslationService } from './i18n/translation.service';
import { Product, OrderResponse } from './models/models';
import { TextKey } from './i18n/translations';

/**
 * Container-Komponente: laedt Produkte (Lade-/Fehlerzustand), orchestriert
 * Warenkorb und Bestellablauf und zeigt die Bestellbestaetigung.
 */
@Component({
  selector: 'app-root',
  imports: [ProductListComponent, CartComponent, OrderConfirmationComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {
  private readonly orderService = inject(OrderService);
  private readonly cart = inject(CartService);
  protected readonly i18n = inject(TranslationService);

  // --- Produktkatalog (Lade-/Fehlerzustand und Retry liefert die Resource) ---
  readonly products = inject(ProductService).productsResource();

  // --- Bestellung ---
  readonly submitting = signal(false);
  readonly orderError = signal<TextKey | null>(null);
  readonly confirmedOrder = signal<OrderResponse | null>(null);

  addToCart(product: Product): void {
    this.cart.add(product);
  }

  checkout(customerName: string): void {
    this.submitting.set(true);
    this.orderError.set(null);
    this.orderService
      .createOrder({ customerName, items: this.cart.toOrderItems() })
      .subscribe({
        next: (order) => {
          this.confirmedOrder.set(order);
          this.cart.clear();
          this.submitting.set(false);
        },
        error: () => {
          this.orderError.set('orderSendError');
          this.submitting.set(false);
        },
      });
  }

  startNewOrder(): void {
    this.confirmedOrder.set(null);
    this.orderError.set(null);
  }
}
