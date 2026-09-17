import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { OrderResponse } from '../../models/models';
import { EuroPipe } from '../../pipes/euro.pipe';

/**
 * Bestaetigung nach erfolgreicher Bestellung: zeigt Bestell-Id, Status
 * und Gesamtsumme. `newOrder` startet eine neue Bestellung.
 */
@Component({
  selector: 'app-order-confirmation',
  standalone: true,
  imports: [EuroPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './order-confirmation.component.html',
  styleUrl: './order-confirmation.component.css',
})
export class OrderConfirmationComponent {
  readonly order = input.required<OrderResponse>();
  readonly newOrder = output<void>();
}
