import { Injectable, computed, signal } from '@angular/core';
import { CartItem, OrderItemRequest, Product } from '../models/models';

/**
 * Signal-first Warenkorb-State. Haelt die Positionen als Signal und leitet
 * abgeleitete Werte (Anzahl, Zwischensumme) als computed-Signals ab.
 */
@Injectable({ providedIn: 'root' })
export class CartService {
  private readonly itemsSignal = signal<CartItem[]>([]);

  /** Alle Positionen im Warenkorb (readonly nach aussen). */
  readonly items = this.itemsSignal.asReadonly();

  /** Gesamtanzahl aller Artikel (Summe der Mengen). */
  readonly totalQuantity = computed(() =>
    this.itemsSignal().reduce((sum, item) => sum + item.quantity, 0),
  );

  /** Zwischensumme in Cent. */
  readonly subtotalCents = computed(() =>
    this.itemsSignal().reduce(
      (sum, item) => sum + item.product.priceCents * item.quantity,
      0,
    ),
  );

  /** Ist der Warenkorb leer? */
  readonly isEmpty = computed(() => this.itemsSignal().length === 0);

  /** Produkt hinzufuegen bzw. Menge erhoehen, wenn bereits enthalten. */
  add(product: Product): void {
    this.itemsSignal.update((items) => {
      const existing = items.find((i) => i.product.id === product.id);
      if (existing) {
        return items.map((i) =>
          i.product.id === product.id ? { ...i, quantity: i.quantity + 1 } : i,
        );
      }
      return [...items, { product, quantity: 1 }];
    });
  }

  /** Menge einer Position setzen. Menge <= 0 entfernt die Position. */
  setQuantity(productId: number, quantity: number): void {
    if (quantity <= 0) {
      this.remove(productId);
      return;
    }
    this.itemsSignal.update((items) =>
      items.map((i) => (i.product.id === productId ? { ...i, quantity } : i)),
    );
  }

  increment(productId: number): void {
    this.itemsSignal.update((items) =>
      items.map((i) =>
        i.product.id === productId ? { ...i, quantity: i.quantity + 1 } : i,
      ),
    );
  }

  decrement(productId: number): void {
    const item = this.itemsSignal().find((i) => i.product.id === productId);
    if (item) {
      this.setQuantity(productId, item.quantity - 1);
    }
  }

  /** Position komplett entfernen. */
  remove(productId: number): void {
    this.itemsSignal.update((items) =>
      items.filter((i) => i.product.id !== productId),
    );
  }

  /** Warenkorb leeren (z.B. nach erfolgreicher Bestellung). */
  clear(): void {
    this.itemsSignal.set([]);
  }

  /** Positionen in das Backend-Format fuer POST /api/orders umwandeln. */
  toOrderItems(): OrderItemRequest[] {
    return this.itemsSignal().map((i) => ({
      productId: i.product.id,
      quantity: i.quantity,
    }));
  }
}
