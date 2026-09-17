import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CartService } from '../../services/cart.service';
import { EuroPipe } from '../../pipes/euro.pipe';

/**
 * Warenkorb-Ansicht: Positionen anzeigen, Mengen aendern, entfernen und
 * Bestellung ausloesen. Der State liegt im signal-basierten CartService;
 * das eigentliche Absenden uebernimmt die Container-Komponente (Output `checkout`).
 */
@Component({
  selector: 'app-cart',
  standalone: true,
  imports: [FormsModule, EuroPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './cart.component.html',
  styleUrl: './cart.component.css',
})
export class CartComponent {
  private readonly cart = inject(CartService);

  /** Laeuft gerade ein POST /api/orders? (von aussen gesteuert) */
  readonly submitting = input(false);

  /** Bestellung ausloesen mit eingegebenem Kundennamen. */
  readonly checkout = output<string>();

  // Signals aus dem CartService fuer das Template
  readonly items = this.cart.items;
  readonly subtotalCents = this.cart.subtotalCents;
  readonly totalQuantity = this.cart.totalQuantity;
  readonly isEmpty = this.cart.isEmpty;

  readonly customerName = signal('');

  readonly canSubmit = computed(
    () => !this.isEmpty() && this.customerName().trim().length > 0,
  );

  increment(productId: number): void {
    this.cart.increment(productId);
  }

  decrement(productId: number): void {
    this.cart.decrement(productId);
  }

  remove(productId: number): void {
    this.cart.remove(productId);
  }

  submit(): void {
    if (this.canSubmit() && !this.submitting()) {
      this.checkout.emit(this.customerName().trim());
    }
  }
}
