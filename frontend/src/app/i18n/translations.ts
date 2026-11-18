/** Bestellstatus aus dem Backend (enum OrderStatus). */
export type OrderStatus = 'CREATED' | 'PAID' | 'SHIPPED' | 'CANCELLED';

/** Unterstuetzte Sprachen der UI. */
export type Lang = 'de' | 'en-US';

export const SUPPORTED_LANGS: readonly Lang[] = ['de', 'en-US'];

/**
 * Alle UI-Texte. Platzhalter im Format {name} werden von TranslationService.t() ersetzt.
 * Fuer Mengenangaben gibt es eine Singular-Variante mit Suffix `One` (siehe tCount()).
 */
export interface Messages {
  appTitle: string;
  appSubtitle: string;
  languageLabel: string;
  products: string;
  productsLoading: string;
  productsLoadError: string;
  productsEmpty: string;
  retry: string;
  addToCart: string;
  cart: string;
  cartEmpty: string;
  decreaseQuantity: string;
  increaseQuantity: string;
  removeItem: string;
  remove: string;
  subtotal: string;
  subtotalOne: string;
  name: string;
  namePlaceholder: string;
  submitOrder: string;
  submittingOrder: string;
  orderSendError: string;
  orderConfirmationLabel: string;
  thankYou: string;
  orderNumber: string;
  status: string;
  orderStatus: Record<OrderStatus, string>;
  total: string;
  newOrder: string;
}

/** Schluessel aller einfachen Texte (ohne verschachtelte Maps wie orderStatus). */
export type TextKey = { [K in keyof Messages]: Messages[K] extends string ? K : never }[keyof Messages];

export const MESSAGES: Record<Lang, Messages> = {
  de: {
    appTitle: 'Lebensmittel-Bestellung',
    appSubtitle: 'OpenTelemetry-Demo',
    languageLabel: 'Sprache',
    products: 'Produkte',
    productsLoading: 'Produkte werden geladen…',
    productsLoadError: 'Produkte konnten nicht geladen werden. Bitte spaeter erneut versuchen.',
    productsEmpty: 'Aktuell sind keine Produkte verfuegbar.',
    retry: 'Erneut versuchen',
    addToCart: 'In den Warenkorb',
    cart: 'Warenkorb',
    cartEmpty: 'Der Warenkorb ist leer.',
    decreaseQuantity: 'Menge verringern',
    increaseQuantity: 'Menge erhoehen',
    removeItem: 'Position entfernen',
    remove: 'Entfernen',
    subtotal: 'Zwischensumme ({count} Artikel)',
    subtotalOne: 'Zwischensumme (1 Artikel)',
    name: 'Name',
    namePlaceholder: 'Ihr Name',
    submitOrder: 'Bestellung absenden',
    submittingOrder: 'Bestellung wird gesendet…',
    orderSendError: 'Die Bestellung konnte nicht gesendet werden. Bitte erneut versuchen.',
    orderConfirmationLabel: 'Bestellbestaetigung',
    thankYou: 'Vielen Dank fuer Ihre Bestellung!',
    orderNumber: 'Bestell-Nr.',
    status: 'Status',
    orderStatus: { CREATED: 'Eingegangen', PAID: 'Bezahlt', SHIPPED: 'Versendet', CANCELLED: 'Storniert' },
    total: 'Gesamtsumme',
    newOrder: 'Neue Bestellung',
  },
  'en-US': {
    appTitle: 'Grocery Order',
    appSubtitle: 'OpenTelemetry Demo',
    languageLabel: 'Language',
    products: 'Products',
    productsLoading: 'Loading products…',
    productsLoadError: 'Products could not be loaded. Please try again later.',
    productsEmpty: 'No products are currently available.',
    retry: 'Try again',
    addToCart: 'Add to cart',
    cart: 'Shopping Cart',
    cartEmpty: 'Your cart is empty.',
    decreaseQuantity: 'Decrease quantity',
    increaseQuantity: 'Increase quantity',
    removeItem: 'Remove item',
    remove: 'Remove',
    subtotal: 'Subtotal ({count} items)',
    subtotalOne: 'Subtotal (1 item)',
    name: 'Name',
    namePlaceholder: 'Your name',
    submitOrder: 'Place order',
    submittingOrder: 'Placing order…',
    orderSendError: 'Your order could not be sent. Please try again.',
    orderConfirmationLabel: 'Order confirmation',
    thankYou: 'Thank you for your order!',
    orderNumber: 'Order no.',
    status: 'Status',
    orderStatus: { CREATED: 'Received', PAID: 'Paid', SHIPPED: 'Shipped', CANCELLED: 'Canceled' },
    total: 'Total',
    newOrder: 'New order',
  },
};

/**
 * Uebersetzungen fuer die (deutschen) Katalogdaten aus dem Backend-Seed
 * (V2__seed_products.sql). Unbekannte Texte werden unveraendert angezeigt.
 */
export const CATALOG_EN_US: Readonly<Record<string, string>> = {
  // Kategorien
  'Obst & Gemüse': 'Fruits & Vegetables',
  'Backwaren': 'Bakery',
  'Molkerei': 'Dairy',
  'Getränke': 'Beverages',
  // Produktnamen
  'Bio-Äpfel 1 kg': 'Organic Apples 1 kg',
  'Bananen 1 kg': 'Bananas 1 kg',
  'Bauernbrot 750 g': 'Farmhouse Bread 750 g',
  'Butter-Croissant': 'Butter Croissant',
  'Vollmilch 1 L': 'Whole Milk 1 L',
  'Naturjoghurt 500 g': 'Plain Yogurt 500 g',
  'Mineralwasser 6x1 L': 'Sparkling Mineral Water 6 × 1 L',
  'Orangensaft 1 L': 'Orange Juice 1 L',
  // Beschreibungen
  'Knackige Äpfel aus regionalem Bio-Anbau, lose.': 'Crisp apples from local organic farms, sold loose.',
  'Süße Fairtrade-Bananen, ideal für den Snack.': 'Sweet Fair Trade bananas, perfect for snacking.',
  'Kräftiges Roggenmischbrot aus dem Steinofen.': 'Hearty rye blend bread, baked in a stone oven.',
  'Frisches Croissant aus reinem Butterteig.': 'Fresh croissant made with all-butter pastry.',
  'Frische Vollmilch 3,5 % Fett aus der Region.': 'Fresh local whole milk, 3.5% fat.',
  'Cremiger Naturjoghurt 3,5 % Fett, ohne Zusätze.': 'Creamy plain yogurt, 3.5% fat, no additives.',
  'Natürliches Mineralwasser, spritzig, im Sixpack.': 'Natural sparkling mineral water, 6-pack.',
  'Direktsaft aus 100 % Orangen, nicht aus Konzentrat.': '100% orange juice, not from concentrate.',
};
