import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { ProductListComponent } from './components/product-list/product-list.component';
import { CartComponent } from './components/cart/cart.component';
import { OrderConfirmationComponent } from './components/order-confirmation/order-confirmation.component';
import { ProductService } from './services/product.service';
import { OrderService } from './services/order.service';
import { CartService } from './services/cart.service';
import { Product, OrderResponse } from './models/models';

/**
 * Container-Komponente: laedt Produkte (Lade-/Fehlerzustand), orchestriert
 * Warenkorb und Bestellablauf und zeigt die Bestellbestaetigung.
 */
@Component({
  selector: 'app-root',
  standalone: true,
  imports: [ProductListComponent, CartComponent, OrderConfirmationComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {
  private readonly productService = inject(ProductService);
  private readonly orderService = inject(OrderService);
  private readonly cart = inject(CartService);

  // --- Produktkatalog ---
  readonly products = signal<Product[]>([]);
  readonly productsLoading = signal(false);
  readonly productsError = signal<string | null>(null);

  // --- Bestellung ---
  readonly submitting = signal(false);
  readonly orderError = signal<string | null>(null);
  readonly confirmedOrder = signal<OrderResponse | null>(null);

  constructor() {
    this.loadProducts();
  }

  loadProducts(): void {
    this.productsLoading.set(true);
    this.productsError.set(null);
    this.productService.getProducts().subscribe({
      next: (products) => {
        this.products.set(products);
        this.productsLoading.set(false);
      },
      error: () => {
        this.productsError.set(
          'Produkte konnten nicht geladen werden. Bitte spaeter erneut versuchen.',
        );
        this.productsLoading.set(false);
      },
    });
  }

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
          this.orderError.set(
            'Die Bestellung konnte nicht gesendet werden. Bitte erneut versuchen.',
          );
          this.submitting.set(false);
        },
      });
  }

  startNewOrder(): void {
    this.confirmedOrder.set(null);
    this.orderError.set(null);
  }
}
