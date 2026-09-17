/** Produkt aus GET /api/products. Preis kommt als Cent-Integer vom Backend. */
export interface Product {
  id: number;
  name: string;
  description: string;
  priceCents: number;
  category: string;
}

/** Eine Position im Warenkorb: Produkt + gewaehlte Menge. */
export interface CartItem {
  product: Product;
  quantity: number;
}

/** Eine Position im Bestell-Request (Body von POST /api/orders). */
export interface OrderItemRequest {
  productId: number;
  quantity: number;
}

/** Body von POST /api/orders. */
export interface CreateOrderRequest {
  customerName: string;
  items: OrderItemRequest[];
}

/** Eine Position in der Bestell-Antwort. */
export interface OrderItemResponse {
  productId: number;
  name?: string;
  quantity: number;
  priceCents?: number;
}

/** Antwort von POST /api/orders. */
export interface OrderResponse {
  id: number;
  status: string;
  totalCents: number;
  createdAt: string;
  items: OrderItemResponse[];
}
