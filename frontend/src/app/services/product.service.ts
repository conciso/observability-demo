import { Injectable } from '@angular/core';
import { HttpResourceRef, httpResource } from '@angular/common/http';
import { Product } from '../models/models';

/**
 * Laedt den Produktkatalog vom Backend.
 * Nutzt bewusst eine relative URL (/api/...), damit nginx sie an das Backend proxyt.
 */
@Injectable({ providedIn: 'root' })
export class ProductService {
  /**
   * Erzeugt eine Resource fuer den Katalog (Lade-/Fehlerzustand, reload()).
   * Muss im Injection Context aufgerufen werden, z.B. in einem Feld-Initializer.
   */
  productsResource(): HttpResourceRef<Product[]> {
    return httpResource<Product[]>(() => '/api/products', { defaultValue: [] });
  }
}
