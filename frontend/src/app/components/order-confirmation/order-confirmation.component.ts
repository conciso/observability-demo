import { ChangeDetectionStrategy, Component, inject, input, output } from '@angular/core';
import { OrderResponse } from '../../models/models';
import { EuroPipe } from '../../pipes/euro.pipe';
import { TranslationService } from '../../i18n/translation.service';

/**
 * Bestaetigung nach erfolgreicher Bestellung: zeigt Bestell-Id, Status
 * und Gesamtsumme. `newOrder` startet eine neue Bestellung.
 */
@Component({
  selector: 'app-order-confirmation',
  imports: [EuroPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './order-confirmation.component.html',
  styleUrl: './order-confirmation.component.css',
})
export class OrderConfirmationComponent {
  protected readonly i18n = inject(TranslationService);

  readonly order = input.required<OrderResponse>();
  readonly newOrder = output<void>();
}
