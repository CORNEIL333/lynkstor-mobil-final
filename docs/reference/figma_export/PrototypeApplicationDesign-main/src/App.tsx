import { useState, useRef, useEffect } from 'react'
import {
  Home,
  ShoppingCart,
  Package,
  Bot,
  Search,
  QrCode,
  Plus,
  Minus,
  Trash2,
  CreditCard,
  Banknote,
  Smartphone,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  Bell,
  Wifi,
  Moon,
  Sun,
  WifiOff,
  Cloud,
  AlertTriangle,
  TrendingUp,
  TrendingDown,
  CheckCircle,
  ArrowUpRight,
  Mic,
  Send,
  Sparkles,
  X,
  BarChart3,
  Camera,
  ShoppingBag,
  Clock,
  UserPlus,
  Menu,
  Check,
  Store,
  ArrowRight,
  ChevronLeft,
  BookOpen,
  MessageSquare,
  Shield,
  Building,
  RotateCcw,
  Users,
  Info,
  Sliders,
  RefreshCw,
  Zap,
  ToggleLeft,
  ToggleRight,
  Lock,
  Printer,
  PieChart,
  Award,
  Gift,
  Tag,
  FileText,
  ArrowLeft,
  UserCheck,
  User,
  ClipboardList,
} from 'lucide-react'
import lynkstorLogo from '@/imports/LynkstorLogo.png';
import { Button, Input, Select } from './ui/primitives';
import { Dialog } from './ui/primitives';
import { ShopAvatar, ShopIdentity } from './ui/ShopIdentity';
import { ThemePicker } from './ui/ThemeProvider';
import { SyncIndicator, useSyncTransport, type SyncTransport } from './ui/SyncIndicator';
import { LynkstorBottomNavigation, LynkstorHeader, LynkstorMetricCard, LynkstorStatusBadge } from './design-system';
import { getSectorCatalogue } from './data/catalogue/catalogue';
import type { CatalogueItem } from './data/catalogue/types';
import { createLocalId } from './data/catalogue/local-id';
import { CatalogueSelector } from './components/CatalogueSelector';
import { configureTenantCatalogueProduct, deductTenantCatalogueStock, selectCatalogueReferences, setTenantCatalogueSellingPrice, type TenantCatalogueEvent, type TenantCatalogueProduct, type TenantCatalogueStatus } from './data/catalogue/tenant-catalogue';
import { clearShopSession, loadShopSession, loadTenantCatalogue, saveShopSession, saveTenantCatalogue } from './data/catalogue/tenant-storage';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface LoyaltySettings {
  earnRateFcfaPerPoint: number
  redemptionValuePerPoint: number
  minRedemptionPoints: number
  loyaltyEnabled: boolean
}

export interface CustomerLoyalty {
  id: string
  name: string
  phone: string
  pointsBalance: number
  totalSpent: number
  visitCount: number
  tier: 'Bronze' | 'Argent' | 'Or' | 'VIP'
  lastVisitDate: string
}

export interface PromotionCoupon {
  id: string
  code: string
  discountType: 'percent' | 'fixed'
  discountValue: number
  minOrderAmount: number
  active: boolean
  usageCount: number
}

type Tab = 'accueil' | 'vente' | 'stock' | 'assistant'

type WorkspaceRole = 'proprietaire' | 'gestionnaire' | 'caissier' | 'vendeur' | 'magasinier'
type CustomerOrderStatus = 'a_envoyer' | 'nouvelle' | 'acceptee' | 'en_preparation' | 'prete' | 'remise' | 'terminee' | 'refusee'

interface CommercePolicy {
  customerDataVisibility: 'service_only' | 'team_authorised'
  stockReservationMoment: 'acceptation' | 'preparation' | 'remise'
  pwaPaymentMoment: 'commande' | 'remise' | 'au_choix'
  sensitiveActionApproval: 'proprietaire' | 'supervision' | 'delegation'
  workspaceMode: 'un_role_actif' | 'roles_cumules'
}

interface ClientPwaOrder {
  id: string
  shopName: string
  date: string
  status: string
  payStatus: 'simulation' | 'non_requis' | 'en_attente'
  payMethod: string
  items: Array<{ name: string; qty: number; price: number }>
  total: number
  customerName?: string
  customerPhone?: string
  fulfillmentStatus?: CustomerOrderStatus
}

const WORKSPACE_CONFIG: Record<WorkspaceRole, { label: string; description: string; tabs: Tab[]; tone: string }> = {
  proprietaire: { label: 'Propriétaire', description: 'Pilotage consolidé, boutiques et règles', tabs: ['accueil', 'vente', 'stock', 'assistant'], tone: 'bg-indigo-50 text-indigo-700 border-indigo-200' },
  gestionnaire: { label: 'Gestionnaire', description: 'Pilotage de la boutique et commandes', tabs: ['accueil', 'vente', 'stock', 'assistant'], tone: 'bg-purple-50 text-purple-700 border-purple-200' },
  caissier: { label: 'Caissier', description: 'Vente, paniers et remise client', tabs: ['accueil', 'vente', 'assistant'], tone: 'bg-blue-50 text-blue-700 border-blue-200' },
  vendeur: { label: 'Vendeur', description: 'Vente assistée et préparation', tabs: ['accueil', 'vente', 'assistant'], tone: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
  magasinier: { label: 'Magasinier', description: 'Stock, réservations et préparation', tabs: ['accueil', 'stock', 'assistant'], tone: 'bg-amber-50 text-amber-700 border-amber-200' },
}

const DEFAULT_COMMERCE_POLICY: CommercePolicy = {
  customerDataVisibility: 'team_authorised',
  stockReservationMoment: 'acceptation',
  pwaPaymentMoment: 'au_choix',
  sensitiveActionApproval: 'supervision',
  workspaceMode: 'un_role_actif',
}

function compactCustomerName(name?: string): string | undefined {
  const cleaned = name?.trim().replace(/\s+/g, ' ')
  if (!cleaned) return undefined
  const characters = Array.from(cleaned)
  return characters.length > 12 ? `${characters.slice(0, 12).join('')}…` : cleaned
}

export interface EnterpriseInfo {
  companyName: string
  niu?: string
  rccm?: string
  headOfficeCity: string
  subscriptionPlan: 'Gratuit' | 'Lynkstor Pro' | 'Entreprise Multi-boutiques'
}

export interface ShopStaff {
  id: string
  name: string
  role: 'caisse' | 'stock' | 'supervision'
}

export interface ShopOpeningHours {
  openTime: string
  closeTime: string
  days: string
}

export interface ShopLegalInfo {
  niu?: string
  rccm?: string
}

export interface ShopOwnerItem {
  id: string
  name: string
  city: string
  hours: ShopOpeningHours
  staff: ShopStaff[]
  revenue7d: number
  isCurrentAppShop?: boolean
  legalInfo?: ShopLegalInfo
  sector?: string
}

interface Product {
  id: string
  name: string
  price: number
  costPrice?: number
  stock: number
  category: string
  emoji: string
  /** Image choisie par la boutique, conservée localement dans cette démonstration. */
  imageUrl?: string
  alert?: 'low' | 'critical'
  packaging?: 'unite' | 'carton' | 'paquet'
  unitsPerPack?: number
  allowPriceNegotiation?: boolean
  allowCreditSale?: boolean
  isUncatalogued?: boolean
  /** Référence fournisseur conservée séparément du prix de vente de la boutique. */
  catalogueReference?: CatalogueItem
  salesUnit?: string
  catalogueStatus?: TenantCatalogueStatus
  tenantCatalogueProduct?: TenantCatalogueProduct
}

interface CreditMovement {
  id: string
  date: string
  type: 'sale' | 'repayment'
  amount: number
  description?: string
}

interface CreditAccount {
  id: string
  name: string
  phone?: string
  movements: CreditMovement[]
}

export interface ProductMovement {
  id: string
  date: string
  type: 'sale' | 'purchase' | 'adjustment'
  qty: number
  description: string
}

export interface Expense {
  id: string
  date: string
  timestamp: number
  amount: number
  category: 'loyer' | 'energie' | 'transport' | 'salaires' | 'entretien' | 'telecom' | 'taxes' | 'divers'
  paymentSource: 'especes' | 'mobile_money' | 'personnel'
  description: string
  receiptPhotoUrl?: string
}

export const EXPENSE_CATEGORIES: {
  key: 'loyer' | 'energie' | 'transport' | 'salaires' | 'entretien' | 'telecom' | 'taxes' | 'divers'
  label: string
  emoji: string
  color: string
}[] = [
    { key: 'loyer', label: 'Loyer & Emplacement', emoji: '🏠', color: 'bg-blue-50 text-blue-700 border-blue-200' },
    { key: 'energie', label: 'Énergie & Eau', emoji: '💡', color: 'bg-amber-50 text-amber-700 border-amber-200' },
    { key: 'transport', label: 'Transport & Livraisons', emoji: '🚚', color: 'bg-purple-50 text-purple-700 border-purple-200' },
    { key: 'salaires', label: 'Salaires & Avances', emoji: '👷', color: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
    { key: 'entretien', label: 'Entretien & Réparations', emoji: '🔧', color: 'bg-indigo-50 text-indigo-700 border-indigo-200' },
    { key: 'telecom', label: 'Télécom & Crédit', emoji: '📶', color: 'bg-cyan-50 text-cyan-700 border-cyan-200' },
    { key: 'taxes', label: 'Taxes & Formalités', emoji: '📜', color: 'bg-rose-50 text-rose-700 border-rose-200' },
    { key: 'divers', label: 'Divers & Imprévus', emoji: '📦', color: 'bg-gray-50 text-gray-700 border-gray-200' },
  ]

export const INITIAL_EXPENSES: Expense[] = [
  { id: 'exp-1', date: '25/07/2025', timestamp: Date.now() - 3600000 * 2, amount: 2500, category: 'transport', paymentSource: 'especes', description: 'Course taxi livraison stock riz' },
  { id: 'exp-2', date: '25/07/2025', timestamp: Date.now() - 3600000 * 5, amount: 5000, category: 'telecom', paymentSource: 'mobile_money', description: 'Rechargement connexion Internet boutique' },
  { id: 'exp-3', date: '24/07/2025', timestamp: Date.now() - 86400000, amount: 15000, category: 'energie', paymentSource: 'especes', description: 'Facture électricité ENEO Juillet' },
  { id: 'exp-4', date: '22/07/2025', timestamp: Date.now() - 86400000 * 3, amount: 20000, category: 'salaires', paymentSource: 'especes', description: 'Avance sur salaire vendeur Moussa' },
]

interface CartItem {
  product: Product
  qty: number
}

interface ChatMessage {
  id: string
  role: 'user' | 'ai'
  text: string
  time: string
}

// ─── Data ─────────────────────────────────────────────────────────────────────

const PRODUCTS: Product[] = [
  { id: '1', name: 'Huile Végétale 1L', price: 1500, costPrice: 1200, stock: 48, category: 'Épicerie', emoji: '🫒', packaging: 'carton', unitsPerPack: 12, allowPriceNegotiation: true },
  { id: '2', name: 'Riz Basmati 5kg', price: 4200, costPrice: 3400, stock: 7, category: 'Épicerie', emoji: '🌾', alert: 'low', packaging: 'paquet', unitsPerPack: 5, allowPriceNegotiation: true, allowCreditSale: true },
  { id: '3', name: 'Lait Concentré 397g', price: 850, costPrice: 650, stock: 32, category: 'Épicerie', emoji: '🥛' },
  { id: '4', name: 'Sucre 1kg', price: 650, costPrice: 500, stock: 2, category: 'Épicerie', emoji: '🍬', alert: 'critical', allowCreditSale: true },
  { id: '5', name: 'Savon de Marseille', price: 400, costPrice: 280, stock: 24, category: 'Hygiène', emoji: '🧼' },
  { id: '6', name: 'Farine de Blé 1kg', price: 550, costPrice: 420, stock: 18, category: 'Épicerie', emoji: '🌾' },
  { id: '7', name: 'Tomate Concentrée 70g', price: 250, costPrice: 180, stock: 60, category: 'Épicerie', emoji: '🍅' },
  { id: '8', name: 'Sardines en conserve', price: 700, costPrice: 520, stock: 15, category: 'Conserves', emoji: '🐟' },
  { id: '9', name: 'Café Soluble 200g', price: 2200, costPrice: 1750, stock: 9, category: 'Boissons', emoji: '☕', alert: 'low' },
  { id: '10', name: 'Biscuits Petits-Lu', price: 450, costPrice: 320, stock: 40, category: 'Biscuiterie', emoji: '🍪' },
  { id: '11', name: 'Eau Minérale 1.5L', price: 300, costPrice: 200, stock: 72, category: 'Boissons', emoji: '💧', packaging: 'carton', unitsPerPack: 6 },
  { id: '12', name: 'Sel de Table 1kg', price: 200, costPrice: 140, stock: 55, category: 'Épicerie', emoji: '🧂' },
]

function productFromTenantCatalogue(entry: TenantCatalogueProduct): Product {
  return {
    id: entry.id,
    name: entry.name,
    price: entry.sellingPrice ?? 0,
    stock: entry.stockOnHand ?? entry.initialStock ?? 0,
    category: entry.category,
    emoji: '•',
    salesUnit: entry.salesUnit ?? 'unité',
    catalogueStatus: entry.status,
    tenantCatalogueProduct: entry,
  }
}

const INITIAL_CREDIT_ACCOUNTS: CreditAccount[] = [
  {
    id: 'acc-1',
    name: 'Maman Sarah',
    phone: '699123456',
    movements: [
      { id: 'm-1', date: '22/07/2025', type: 'sale', amount: 3500, description: 'Riz Basmati · Huile' },
      { id: 'm-2', date: '24/07/2025', type: 'repayment', amount: 2000, description: 'Remboursement partiel' },
      { id: 'm-3', date: '25/07/2025', type: 'sale', amount: 5000, description: 'Sucre · Farine · Eau' },
    ],
  },
  {
    id: 'acc-2',
    name: 'Papa Oumarou',
    phone: '677987654',
    movements: [
      { id: 'm-4', date: '20/07/2025', type: 'sale', amount: 4200, description: 'Huile Végétale 1L × 2' },
      { id: 'm-5', date: '24/07/2025', type: 'repayment', amount: 4200, description: 'Remboursement total' },
    ],
  },
  {
    id: 'acc-3',
    name: 'Mme Ngo',
    phone: '655443322',
    movements: [
      { id: 'm-6', date: '25/07/2025', type: 'sale', amount: 1800, description: 'Biscuits · Café' },
    ],
  },
]

const INITIAL_LOYALTY_SETTINGS: LoyaltySettings = {
  earnRateFcfaPerPoint: 1000,
  redemptionValuePerPoint: 10,
  minRedemptionPoints: 50,
  loyaltyEnabled: true,
}

const INITIAL_CUSTOMERS: CustomerLoyalty[] = [
  { id: 'cust-1', name: 'M. Paul Etoa', phone: '699112233', pointsBalance: 140, totalSpent: 140000, visitCount: 12, tier: 'Or', lastVisitDate: 'Hier' },
  { id: 'cust-2', name: 'Mme Chantal Ngo', phone: '677445566', pointsBalance: 80, totalSpent: 80000, visitCount: 6, tier: 'Argent', lastVisitDate: 'Il y a 3j' },
  { id: 'cust-3', name: 'M. Jean Ndongo', phone: '655889900', pointsBalance: 250, totalSpent: 250000, visitCount: 20, tier: 'VIP', lastVisitDate: "Aujourd'hui" },
  { id: 'cust-4', name: 'Mme Suzanne Belinga', phone: '690001122', pointsBalance: 15, totalSpent: 15000, visitCount: 2, tier: 'Bronze', lastVisitDate: 'Il y a 35j' },
]

const INITIAL_COUPONS: PromotionCoupon[] = [
  { id: 'coup-1', code: 'BIENVENUE10', discountType: 'percent', discountValue: 10, minOrderAmount: 5000, active: true, usageCount: 24 },
  { id: 'coup-2', code: 'VIP2000', discountType: 'fixed', discountValue: 2000, minOrderAmount: 15000, active: true, usageCount: 8 },
  { id: 'coup-3', code: 'SOLDE15', discountType: 'percent', discountValue: 15, minOrderAmount: 10000, active: false, usageCount: 42 },
]

function getAccountBalance(account: CreditAccount): number {
  return account.movements.reduce((sum, m) => sum + (m.type === 'sale' ? m.amount : -m.amount), 0)
}

function getInitialShops(currentShopName: string, currentCity: string): ShopOwnerItem[] {
  return [
    {
      id: 'shop-1',
      name: currentShopName?.trim() || 'Épicerie du Marché Central',
      city: currentCity?.trim() || 'Douala',
      hours: { openTime: '07:30', closeTime: '20:00', days: 'Lun - Sam' },
      revenue7d: 342500,
      isCurrentAppShop: true,
      sector: 'Épicerie',
      legalInfo: { niu: 'M051212345678A', rccm: 'RC/DLA/2023/B/1234' },
      staff: [
        { id: 'st-1', name: 'Jean-Paul Mbida', role: 'caisse' },
        { id: 'st-2', name: 'Carine Etoa', role: 'stock' },
        { id: 'st-3', name: 'Samuel Njoya', role: 'supervision' },
      ],
    },
    {
      id: 'shop-2',
      name: 'Lynkstor Mini-Mart Mokolo',
      city: 'Yaoundé',
      hours: { openTime: '08:00', closeTime: '21:00', days: '7j/7' },
      revenue7d: 485000,
      sector: 'Épicerie',
      legalInfo: { niu: 'M081987654321B' },
      staff: [
        { id: 'st-4', name: 'Alice Kamga', role: 'caisse' },
        { id: 'st-5', name: 'Patrick Abena', role: 'stock' },
      ],
    },
    {
      id: 'shop-3',
      name: 'Dépôt Alimentaire Bafoussam',
      city: 'Bafoussam',
      hours: { openTime: '07:00', closeTime: '19:30', days: 'Lun - Sam' },
      revenue7d: 290000,
      sector: 'Épicerie',
      staff: [
        { id: 'st-6', name: 'Emmanuel Fotso', role: 'supervision' },
        { id: 'st-7', name: 'Berthe Toukam', role: 'caisse' },
      ],
    },
  ]
}

const INITIAL_MESSAGES: ChatMessage[] = [
  {
    id: '1',
    role: 'ai',
    text: "Bonjour ! Je suis votre Assistant Lynkstor 🤖\n\nVoici ce que j'observe aujourd'hui :\n• **+12%** de CA vs hier — excellente journée !\n• ⚠️ **2 ruptures imminentes** : Sucre 1kg, Riz Basmati\n• 📋 **3 commandes clients** en attente\n\nComment puis-je vous aider ?",
    time: '08:30',
  },
]

export const SUGGESTIONS = [
  'Quelles sont mes ruptures de stock ?',
  'Résumé des ventes du jour',
  'Produits les plus vendus',
  'Alerte de marge en baisse',
]

interface SectorInfo {
  id: string
  name: string
  emoji: string
  categories: string[]
}

const SECTORS: SectorInfo[] = [
  { id: 'epicerie', name: 'Épicerie', emoji: '🫒', categories: ['Épicerie', 'Hygiène', 'Boissons', 'Conserves', 'Biscuiterie'] },
  { id: 'quincaillerie', name: 'Quincaillerie', emoji: '🔨', categories: ['Outillage', 'Plomberie', 'Électricité', 'Peinture', 'Visserie & Fixation'] },
  { id: 'pharmacie', name: 'Pharmacie', emoji: '💊', categories: ['Médicaments', 'Parapharmacie', 'Hygiène', 'Premiers secours', 'Maternité'] },
  { id: 'parfumerie', name: 'Parfumerie', emoji: '🧴', categories: ['Parfums femme', 'Parfums homme', 'Parfums unisexes et brumes', 'Déodorants', 'Soins du visage', 'Hygiène et corps', 'Soins capillaires', 'Maquillage et accessoires'] },
  { id: 'habillement', name: 'Habillement', emoji: '👕', categories: ['Mode Homme', 'Mode Femme', 'Mode Enfant', 'Chaussures', 'Accessoires'] },
  { id: 'electronique', name: 'Électronique', emoji: '📱', categories: ['Téléphones et smartphones', 'Accessoires mobile', 'Audio et connectivité', 'Télévision et image', 'Petit électroménager', 'Gros électroménager'] },
  { id: 'restaurant', name: 'Restaurant', emoji: '🍽️', categories: ['Plats chauds', 'Boissons', 'Desserts', 'Entrées & Snacks', 'Formules midi'] },
  { id: 'boulangerie', name: 'Boulangerie', emoji: '🥖', categories: ['Pains & Baguettes', 'Viennoiseries', 'Pâtisseries', 'Sandwichs & Salades', 'Boissons'] },
  { id: 'materiaux', name: 'Matériaux de construction', emoji: '🧱', categories: ['Ciment & Agrégats', 'Fer & Armatures', 'Bois & Charpente', 'Étanchéité', 'Carrelage'] },
]

interface OnboardingData {
  tenantId: string
  phoneNumber: string
  shopName: string
  shopCity: string
  sector: string
  categories: string[]
  catalogueSelections: CatalogueItem[]
  catalogueReviewAcknowledged: boolean
}

function OnboardingFlow({ onComplete }: { onComplete: (data: OnboardingData) => void }) {
  const [step, setStep] = useState<'splash' | 'login' | 'shop' | 'sector' | 'categories' | 'catalogue'>('splash')
  const [phoneNumber, setPhoneNumber] = useState('')
  const [shopName, setShopName] = useState('')
  const [shopCity, setShopCity] = useState('Douala')
  const [selectedSector, setSelectedSector] = useState<string>('Épicerie')
  const [selectedCategories, setSelectedCategories] = useState<string[]>(SECTORS[0].categories)

  // Auto transition for Splash
  useEffect(() => {
    if (step === 'splash') {
      const timer = setTimeout(() => setStep('login'), 1600)
      return () => clearTimeout(timer)
    }
  }, [step])

  const handleSelectSector = (sectorName: string) => {
    setSelectedSector(sectorName)
    const found = SECTORS.find((s) => s.name === sectorName)
    if (found) {
      setSelectedCategories([...found.categories])
    }
  }

  const toggleCategory = (cat: string) => {
    setSelectedCategories((prev) =>
      prev.includes(cat) ? prev.filter((c) => c !== cat) : [...prev, cat]
    )
  }

  const isPhoneValid = phoneNumber.replace(/\D/g, '').length >= 9
  const completeOnboarding = (catalogueSelections: CatalogueItem[], catalogueReviewAcknowledged = false) => {
    onComplete({
      tenantId: createLocalId('tenant'),
      phoneNumber,
      shopName: shopName.trim() || 'Épicerie du Marché Central',
      shopCity: shopCity.trim() || 'Douala',
      sector: selectedSector,
      categories: selectedCategories,
      catalogueSelections,
      catalogueReviewAcknowledged,
    })
  }

  return (
    <div
      className="lk-app-canvas flex items-center justify-center min-h-screen"
    >
      {/* Phone Frame Shell */}
      <div
        className="relative flex flex-col overflow-hidden shadow-2xl"
        style={{
          width: 'min(390px, 100vw)',
          height: 'min(844px, 100vh)',
          borderRadius: 'min(44px, 0px)',
          backgroundColor: '#FFFFFF',
        }}
      >
        {/* Status bar */}
        <div
          className="flex items-center justify-between px-6 py-2 flex-shrink-0 z-10"
          style={{ backgroundColor: '#FFFFFF', paddingTop: '10px' }}
        >
          <span className="text-xs font-semibold text-gray-800">9:41</span>
          <div className="flex items-center gap-1.5">
            <Wifi size={13} color="#1D2939" />
            <div className="flex gap-0.5 items-end">
              {[3, 5, 7, 9].map((h) => (
                <div key={h} className="w-1 rounded-sm bg-gray-800" style={{ height: h }} />
              ))}
            </div>
            <div className="flex items-center gap-0.5">
              <div className="w-5 h-2.5 border border-gray-800 rounded-sm p-0.5 flex items-center">
                <div className="bg-gray-800 rounded-[1px] h-full" style={{ width: '80%' }} />
              </div>
            </div>
          </div>
        </div>

        {/* ── SCREEN 1: SPLASH ── */}
        {step === 'splash' && (
          <Button
            onClick={() => setStep('login')}
            className="flex-1 flex flex-col items-center justify-between px-6 py-10 text-center cursor-pointer select-none bg-gradient-to-b from-slate-900 via-indigo-950 to-slate-900 text-white relative overflow-hidden"
          >
            {/* Background Glow Orbs */}
            <div className="absolute -top-20 -left-20 w-64 h-64 bg-indigo-500/20 rounded-full blur-3xl pointer-events-none" />
            <div className="absolute -bottom-20 -right-20 w-64 h-64 bg-purple-500/20 rounded-full blur-3xl pointer-events-none" />

            <div />
            <div className="flex flex-col items-center gap-5 z-10">
              <div className="w-28 h-28 rounded-3xl bg-white/95 backdrop-blur-xl shadow-glow-indigo flex items-center justify-center p-4 border border-white/20 animate-pop-bounce">
                <img src={lynkstorLogo} alt="Lynkstor" className="w-full h-full object-contain" />
              </div>
              <div className="space-y-1">
                <h1 className="text-4xl font-extrabold tracking-tight text-white drop-shadow-sm">Lynkstor</h1>
                <p className="text-xs font-bold text-indigo-300 tracking-widest uppercase bg-indigo-500/20 px-3 py-1 rounded-full border border-indigo-400/30 inline-block">
                  Compagnon de Commerce™
                </p>
              </div>
              <p className="text-xs text-slate-300 max-w-[260px] leading-relaxed mt-1 font-medium">
                La gestion simple, prédictive et intelligente de votre boutique.
              </p>
            </div>

            <div className="w-full space-y-4 z-10">
              <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full badge-glow-green text-xs font-semibold backdrop-blur-md shadow-xs">
                <Wifi size={13} className="animate-pulse" />
                <span>100% Fonctionnel Hors Ligne & Cloud Sync</span>
              </div>
              <p className="text-[11px] text-slate-400 animate-pulse">Touchez l'écran pour démarrer</p>
            </div>
          </Button>
        )}

        {/* ── SCREEN 2: CONNEXION ── */}
        {step === 'login' && (
          <div className="flex-1 flex flex-col px-6 py-6 bg-slate-50 overflow-y-auto justify-between">
            <div className="space-y-6">
              <div className="flex flex-col items-center justify-center gap-3 pt-2">
                <div className="w-[100px] h-[100px] rounded-2xl bg-indigo-50 flex items-center justify-center border border-indigo-100 shadow-xs">
                  <img src={lynkstorLogo} alt="Lynkstor" className="w-full h-full object-contain" />
                </div>
                <div>
                  <p className="text-[10px] font-extrabold text-indigo-600 uppercase tracking-widest text-center">Connexion sécurisée</p>
                  <h2 className="text-xl font-extrabold text-slate-900 leading-tight">Votre numéro mobile</h2>
                </div>
              </div>

              <p className="text-xs text-slate-500 leading-relaxed font-medium">
                Connectez-vous instantanément avec votre numéro de téléphone. Aucun mot de passe ni email requis.
              </p>

              {/* Phone input card */}
              <div className="space-y-2">
                <label className="text-xs font-extrabold text-slate-700">Numéro de téléphone (Cameroun)</label>
                <div className="flex items-center gap-2 bg-white rounded-2xl px-3.5 py-3.5 border border-slate-200 focus-within:border-indigo-600 focus-within:ring-4 focus-within:ring-indigo-100 transition-all shadow-xs">
                  <span className="flex items-center gap-1.5 text-xs font-bold text-slate-800 bg-slate-100 px-2.5 py-1.5 rounded-xl border border-slate-200 shadow-2xs flex-shrink-0">
                    🇨🇲 +237
                  </span>
                  <Input
                    type="tel"
                    value={phoneNumber}
                    onChange={(e) => setPhoneNumber(e.target.value)}
                    placeholder="699 00 00 00"
                    className="flex-1 bg-transparent text-base font-bold text-slate-900 outline-none placeholder:text-slate-400 placeholder:font-normal"
                    autoFocus
                  />
                </div>
                <p className="text-[10px] font-medium text-slate-400">Format : 9 chiffres (ex. 670 12 34 56)</p>
              </div>

              {/* Offline notice */}
              <div className="p-4 rounded-2xl bg-indigo-50/80 border border-indigo-100 flex items-start gap-3 shadow-2xs">
                <div className="w-7 h-7 rounded-xl bg-indigo-600 text-white flex items-center justify-center flex-shrink-0 mt-0.5 shadow-xs">
                  <Wifi size={14} />
                </div>
                <div className="text-xs text-indigo-950">
                  <p className="font-bold mb-0.5">Mode 100% Hors Ligne & Continuous Sync</p>
                  <p className="text-[11px] text-indigo-800 leading-relaxed">
                    Accès immédiat à la vente et au stock même sans Internet. Synchronisation automatique dès la reconnexion.
                  </p>
                </div>
              </div>
            </div>

            <Button
              disabled={!isPhoneValid}
              onClick={() => setStep('shop')}
              className="w-full py-4 rounded-2xl text-white font-extrabold text-sm flex items-center justify-center gap-2 active-press active:scale-[0.98] transition-all disabled:opacity-40 disabled:pointer-events-none mt-6 shadow-glow-indigo bg-gradient-to-r from-indigo-600 to-purple-600"
            >
              <span>Continuer</span>
              <ArrowRight size={18} />
            </Button>
          </div>
        )}

        {/* ── SCREEN 3: CRÉATION BOUTIQUE ── */}
        {step === 'shop' && (
          <div className="flex-1 flex flex-col px-6 py-6 bg-slate-50 overflow-y-auto justify-between">
            <div className="space-y-6">
              <div className="flex items-center justify-between">
                <Button
                  onClick={() => setStep('login')}
                  className="w-9 h-9 rounded-2xl bg-white border border-slate-200 flex items-center justify-center text-slate-600 hover:bg-slate-100 transition-colors shadow-2xs" aria-label="Retour"
                >
                  <ChevronLeft size={18} />
                </Button>
                <span className="text-[11px] font-bold text-indigo-600 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100">Étape 1 sur 3</span>
              </div>

              <div>
                <h2 className="text-xl font-extrabold text-slate-900">Création de votre boutique</h2>
                <p className="text-xs font-medium text-slate-500 mt-1">Indiquez le nom et la ville de votre commerce.</p>
              </div>

              <div className="space-y-4">
                <div className="space-y-1.5">
                  <label className="text-xs font-bold text-slate-700">Nom de la boutique <span className="text-rose-500">*</span></label>
                  <div className="flex items-center gap-2.5 bg-white rounded-2xl px-3.5 py-3.5 border border-slate-200 focus-within:border-indigo-600 focus-within:ring-4 focus-within:ring-indigo-100 shadow-2xs transition-all">
                    <Store size={18} className="text-indigo-600" />
                    <Input
                      type="text"
                      value={shopName}
                      onChange={(e) => setShopName(e.target.value)}
                      placeholder="Ex: Épicerie du Marché Central"
                      className="flex-1 bg-transparent text-sm font-bold text-slate-900 outline-none placeholder:text-slate-400 placeholder:font-normal"
                      autoFocus
                    />
                  </div>
                </div>

                <div className="space-y-1.5">
                  <label className="text-xs font-bold text-slate-700">Ville</label>
                  <div className="flex items-center gap-2.5 bg-white rounded-2xl px-3.5 py-3.5 border border-slate-200 focus-within:border-indigo-600 focus-within:ring-4 focus-within:ring-indigo-100 shadow-2xs transition-all">
                    <Input
                      type="text"
                      value={shopCity}
                      onChange={(e) => setShopCity(e.target.value)}
                      placeholder="Ex: Douala, Yaoundé, Bafoussam..."
                      className="flex-1 bg-transparent text-sm font-bold text-slate-900 outline-none placeholder:text-slate-400 placeholder:font-normal"
                    />
                  </div>
                </div>
              </div>
            </div>

            <Button
              disabled={!shopName.trim()}
              onClick={() => setStep('sector')}
              className="w-full py-4 rounded-2xl text-white font-extrabold text-sm flex items-center justify-center gap-2 active-press active:scale-[0.98] transition-all disabled:opacity-40 disabled:pointer-events-none mt-6 shadow-glow-indigo bg-gradient-to-r from-indigo-600 to-purple-600"
            >
              <span>Continuer</span>
              <ArrowRight size={18} />
            </Button>
          </div>
        )}

        {/* ── SCREEN 4: SÉLECTION SECTEUR ── */}
        {step === 'sector' && (
          <div className="flex-1 flex flex-col px-6 py-6 bg-slate-50 overflow-y-auto justify-between">
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <Button
                  onClick={() => setStep('shop')}
                  className="w-9 h-9 rounded-2xl bg-white border border-slate-200 flex items-center justify-center text-slate-600 hover:bg-slate-100 transition-colors shadow-2xs" aria-label="Retour"
                >
                  <ChevronLeft size={18} />
                </Button>
                <span className="text-[11px] font-bold text-indigo-600 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100">Étape 2 sur 3</span>
              </div>

              <div>
                <h2 className="text-xl font-extrabold text-slate-900">Votre secteur d'activité</h2>
                <p className="text-xs font-medium text-slate-500 mt-0.5">Sélectionnez votre métier pour pré-charger vos catégories.</p>
              </div>

              {/* 3x3 Sector Grid */}
              <div className="grid grid-cols-3 gap-2.5 pt-1">
                {SECTORS.map((sec) => {
                  const isSelected = selectedSector === sec.name
                  return (
                    <Button
                      key={sec.id}
                      onClick={() => handleSelectSector(sec.name)}
                      className={`flex flex-col items-center justify-center p-3 rounded-2xl text-center border-2 transition-all active-press min-h-[92px] ${isSelected
                        ? 'border-indigo-600 bg-indigo-50/80 shadow-glow-indigo scale-[1.02]'
                        : 'border-slate-200/80 bg-white hover:border-slate-300 shadow-2xs'
                        }`}
                    >
                      <span className="text-2xl mb-1">{sec.emoji}</span>
                      <span className={`text-[11px] font-extrabold leading-tight ${isSelected ? 'text-indigo-700' : 'text-slate-800'}`}>
                        {sec.name}
                      </span>
                    </Button>
                  )
                })}
              </div>
            </div>

            <Button
              onClick={() => setStep('categories')}
              className="w-full py-4 rounded-2xl text-white font-extrabold text-sm flex items-center justify-center gap-2 active-press active:scale-[0.98] transition-all mt-6 shadow-glow-indigo bg-gradient-to-r from-indigo-600 to-purple-600 animate-cascade stagger-10"
            >
              <span>Continuer</span>
              <ArrowRight size={18} />
            </Button>
          </div>
        )}

        {/* ── SCREEN 5: SÉLECTION CATÉGORIES ── */}
        {step === 'categories' && (
          <div className="flex-1 flex flex-col px-6 py-6 bg-slate-50 overflow-y-auto justify-between">
            <div className="space-y-4">
              <div className="flex items-center justify-between animate-cascade stagger-1">
                <Button
                  onClick={() => setStep('sector')}
                  className="w-9 h-9 rounded-2xl bg-white border border-slate-200 flex items-center justify-center text-slate-600 hover:bg-slate-100 transition-colors shadow-2xs" aria-label="Retour"
                >
                  <ChevronLeft size={18} />
                </Button>
                <span className="text-[11px] font-bold text-indigo-600 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100">Étape 3 sur 3</span>
              </div>

              <div className="animate-cascade stagger-2">
                <h2 className="text-xl font-extrabold text-slate-900">Catégories initiales</h2>
                <p className="text-xs font-medium text-slate-500 mt-0.5">
                  Ajustez les catégories pour <span className="font-bold text-indigo-600">{selectedSector}</span> :
                </p>
              </div>

              {selectedSector !== 'Épicerie' && (
                <div className={`p-3.5 rounded-2xl border flex items-start gap-2.5 shadow-2xs animate-cascade stagger-3 ${getSectorCatalogue(selectedSector) ? 'bg-emerald-50 border-emerald-200/80' : 'bg-amber-50 border-amber-200/80'}`}>
                  {getSectorCatalogue(selectedSector) ? <BookOpen size={16} className="text-emerald-700 flex-shrink-0 mt-0.5" /> : <AlertTriangle size={16} className="text-amber-600 flex-shrink-0 mt-0.5" />}
                  <p className={`text-[11px] leading-snug ${getSectorCatalogue(selectedSector) ? 'text-emerald-950' : 'text-amber-900'}`}>
                    {getSectorCatalogue(selectedSector)
                      ? <><span className="font-bold">Catalogue Lynkstor disponible :</span> vous choisirez vos références à l’étape suivante. Elles entreront d’abord dans le catalogue interne ; le prix et le stock seront définis dans votre boutique.</>
                      : <><span className="font-bold">Information produit :</span> Vos catégories {selectedSector} sont pré-configurées. Un catalogue sectoriel pourra être ajouté plus tard.</>}
                  </p>
                </div>
              )}

              {/* Checklist */}
              <div className="space-y-2">
                {SECTORS.find((s) => s.name === selectedSector)?.categories.map((cat, idx) => {
                  const isChecked = selectedCategories.includes(cat)
                  const staggerClass = `stagger-${Math.min(idx + 3, 10)}`
                  return (
                    <Button
                      key={cat}
                      onClick={() => toggleCategory(cat)}
                      className={`w-full flex items-center justify-between p-3.5 rounded-2xl border transition-all text-left active-press animate-cascade ${staggerClass} ${isChecked
                        ? 'border-indigo-200 bg-indigo-50/50 text-slate-900 shadow-2xs'
                        : 'border-slate-200/80 bg-white text-slate-400'
                        }`} aria-label="Valider"
                    >
                      <span className="text-sm font-extrabold">{cat}</span>
                      <div
                        className={`w-6 h-6 rounded-xl flex items-center justify-center transition-all ${isChecked ? 'bg-gradient-to-r from-indigo-600 to-purple-600 text-white shadow-xs' : 'border border-slate-300 bg-white'
                          }`}
                      >
                        {isChecked && <Check size={14} strokeWidth={3} />}
                      </div>
                    </Button>
                  )
                })}
              </div>
            </div>

            <Button
              onClick={() => getSectorCatalogue(selectedSector) ? setStep('catalogue') : completeOnboarding([])}
              className="w-full py-4 rounded-2xl text-white font-extrabold text-sm flex items-center justify-center gap-2 active-press active:scale-[0.98] transition-all mt-6 shadow-glow-indigo bg-gradient-to-r from-indigo-600 to-purple-600 animate-cascade stagger-11"
            >
              <Check size={18} />
              <span>{getSectorCatalogue(selectedSector) ? 'Choisir mes produits' : 'Terminer — ouvrir ma boutique'}</span>
            </Button>
          </div>
        )}

        {step === 'catalogue' && (
          <CatalogueSelector
            sector={selectedSector}
            onBack={() => setStep('categories')}
            onSkip={() => completeOnboarding([])}
            confirmLabel="Ajouter à ma boutique"
            onConfirm={(items, reviewAcknowledged) => completeOnboarding(items, reviewAcknowledged)}
          />
        )}
      </div>
    </div>
  )
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function AlertBadge({ level, stock }: { level: 'low' | 'critical'; stock: number }) {
  return stock <= 0 ? (
    <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-red-50 text-red-600">
      <AlertTriangle size={9} /> Rupture
    </span>
  ) : level === 'critical' ? (
    <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-red-50 text-red-600">
      <AlertTriangle size={9} /> Stock critique
    </span>
  ) : (
    <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-amber-50 text-amber-600">
      <AlertTriangle size={9} /> Stock bas
    </span>
  )
}

// ─── Screen: Vente ────────────────────────────────────────────────────────────

interface Cart {
  id: string
  name: string
  items: CartItem[]
  customerId?: string
  customerName?: string
  customerPhone?: string
  origin?: 'counter' | 'pwa_order'
  orderId?: string
}

const DEFAULT_PRODUCT_THUMBNAIL = '/catalogue-thumbnails/produit-illustratif.svg'

function getProductIllustration(product: Product): string {
  if (product.imageUrl) return product.imageUrl
  const category = product.category.toLocaleLowerCase('fr-FR')
  if (category.includes('parfum')) return '/catalogue-thumbnails/parfumerie-parfum-illustratif.png'
  if (category.includes('soin') || category.includes('hygiène')) return '/catalogue-thumbnails/parfumerie-soin-illustratif.png'
  if (category.includes('téléphonie') || category.includes('smartphone')) return '/catalogue-thumbnails/electronique-smartphone-illustratif.png'
  if (category.includes('électronique') || category.includes('électroménager')) return '/catalogue-thumbnails/electronique-electromenager-illustratif.png'
  return DEFAULT_PRODUCT_THUMBNAIL
}

function ProductThumbnail({ product, className = '', fit = 'contain' }: { product: Product; className?: string; fit?: 'contain' | 'cover' }) {
  const [src, setSrc] = useState(() => getProductIllustration(product))

  useEffect(() => {
    setSrc(getProductIllustration(product))
  }, [product.category, product.imageUrl])

  return (
    <img
      src={src}
      alt={product.imageUrl ? `Image de ${product.name}` : `Illustration de ${product.name}`}
      onError={() => setSrc(DEFAULT_PRODUCT_THUMBNAIL)}
      className={`block ${fit === 'contain' ? 'object-contain' : 'object-cover'} ${className}`}
      loading="lazy"
    />
  )
}

function productReference(product: Product): string {
  return product.catalogueReference?.sku?.trim() || `REF-${String(product.id).toUpperCase()}`
}

function ProductStockBadge({ product, publicView = false }: { product: Product; publicView?: boolean }) {
  const isUnavailable = product.stock <= 0
  const isCritical = !isUnavailable && product.alert === 'critical'
  const isLimited = !isCritical && product.alert === 'low'
  const label = isUnavailable || isCritical
    ? (publicView ? 'Indisponible' : 'Rupture')
    : isLimited
      ? (publicView ? 'Stock limité' : 'Stock faible')
      : 'En stock'
  const tone = publicView
    ? isUnavailable || isCritical
      ? 'border-red-800 bg-red-950 text-red-300'
      : isLimited
        ? 'border-amber-800 bg-amber-950 text-amber-300'
        : 'border-emerald-800 bg-emerald-950 text-emerald-300'
    : isUnavailable || isCritical
      ? 'border-red-200 bg-red-50 text-red-700'
      : isLimited
        ? 'border-amber-200 bg-amber-50 text-amber-800'
        : 'border-emerald-200 bg-emerald-50 text-emerald-700'

  return (
    <span className={`inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full border ${tone}`} title={label} aria-label={label}>
      {isUnavailable || isCritical ? <AlertTriangle size={14} strokeWidth={2.5} /> : isLimited ? <AlertTriangle size={14} strokeWidth={2.5} /> : <CheckCircle size={15} strokeWidth={2.5} />}
      <span className="sr-only">{label}</span>
    </span>
  )
}

interface PostSaleStockPrompt {
  product: Product
  source: 'central' | 'uncatalogued'
}

interface DraftPriceResult {
  product?: Product
  error?: string
}

interface VenteScreenProps {
  carts: Cart[]
  setCarts: React.Dispatch<React.SetStateAction<Cart[]>>
  activeCartId: string
  setActiveCartId: (id: string) => void
  cartOpen: boolean
  setCartOpen: (open: boolean) => void
  products: Product[]
  setProducts: React.Dispatch<React.SetStateAction<Product[]>>
  creditAccounts: CreditAccount[]
  setCreditAccounts: React.Dispatch<React.SetStateAction<CreditAccount[]>>
  activeSector: string
  onSetCatalogueDraftPrice: (product: Product, sellingPrice: number) => DraftPriceResult
  onActivateCatalogueProduct: (product: Product) => string | null
  onDeductCatalogueStock: (items: CartItem[]) => string | null
  catalogueDisplay: 'grid' | 'list'
  showCatalogueImages: boolean
  showToast?: (msg: string) => void
}

function VenteScreen({
  carts,
  setCarts,
  activeCartId,
  setActiveCartId,
  cartOpen,
  setCartOpen,
  products,
  setProducts,
  creditAccounts,
  setCreditAccounts,
  activeSector,
  onSetCatalogueDraftPrice,
  onActivateCatalogueProduct,
  onDeductCatalogueStock,
  catalogueDisplay,
  showCatalogueImages,
  showToast,
}: VenteScreenProps) {
  const [search, setSearch] = useState('')
  const [paymentOpen, setPaymentOpen] = useState(false)
  const [payMethod, setPayMethod] = useState<'especes' | 'mobile' | 'mixte' | 'credit'>('especes')
  const [success, setSuccess] = useState(false)
  const [successText, setSuccessText] = useState('Vente confirmée !')
  const [pickerProduct, setPickerProduct] = useState<Product | null>(null)
  const [pickerQty, setPickerQty] = useState(1)

  // Credit sale state
  const [creditSaleOpen, setCreditSaleOpen] = useState(false)
  const [selectedDebtorId, setSelectedDebtorId] = useState<string>(creditAccounts[0]?.id || '')
  const [isNewDebtor, setIsNewDebtor] = useState(false)
  const [newDebtorName, setNewDebtorName] = useState('')
  const [newDebtorPhone, setNewDebtorPhone] = useState('')

  // Uncatalogued item state
  const [uncataloguedModalOpen, setUncataloguedModalOpen] = useState(false)
  const [uncataloguedName, setUncataloguedName] = useState('')
  const [uncataloguedPrice, setUncataloguedPrice] = useState('')
  const [postCheckoutStockPrompts, setPostCheckoutStockPrompts] = useState<PostSaleStockPrompt[]>([])
  const [postStockCategory, setPostStockCategory] = useState(activeSector || 'Épicerie')
  const [postStockQty, setPostStockQty] = useState('')
  const [postStockPrice, setPostStockPrice] = useState('')
  const [pendingFirstSale, setPendingFirstSale] = useState<{ product: Product; qty: number } | null>(null)
  const [firstSalePrice, setFirstSalePrice] = useState('')

  // Barcode scanner simulator state
  const [barcodeScanOpen, setBarcodeScanOpen] = useState(false)
  const [barcodeStatus, setBarcodeStatus] = useState<'scanning' | 'found' | 'not_found'>('scanning')
  const [scannedProduct, setScannedProduct] = useState<Product | null>(null)

  // Vente Assistée states: Remise & Devis
  const [discountModalOpen, setDiscountModalOpen] = useState(false)
  const [discountPercent, setDiscountPercent] = useState<number>(0)
  const [appliedDiscount, setAppliedDiscount] = useState<number>(0)

  const [createDevisModalOpen, setCreateDevisModalOpen] = useState(false)
  const [devisClientName, setDevisClientName] = useState('')
  const [devisClientPhone, setDevisClientPhone] = useState('')

  const [devisListModalOpen, setDevisListModalOpen] = useState(false)
  const [devisList, setDevisList] = useState<{ id: string; code: string; clientName: string; date: string; items: CartItem[]; total: number }[]>([
    {
      id: 'dev-1',
      code: 'DEV-2026-001',
      clientName: 'Restaurant Le Chanti',
      date: '25/07/2025',
      items: [{ product: PRODUCTS[0], qty: 10 }, { product: PRODUCTS[1], qty: 5 }],
      total: 36000,
    },
  ])

  // Loyalty & Coupon states in VenteScreen
  const [selectedLoyaltyCustomer, setSelectedLoyaltyCustomer] = useState<CustomerLoyalty | null>(null)
  const [attachCustomerModalOpen, setAttachCustomerModalOpen] = useState(false)
  const [couponInput, setCouponInput] = useState('')
  const [appliedCouponCode, setAppliedCouponCode] = useState('')
  const [appliedCouponDiscount, setAppliedCouponDiscount] = useState(0)
  const [redeemedPoints, setRedeemedPoints] = useState(0)
  const [pointsDiscount, setPointsDiscount] = useState(0)
  const [newCustName, setNewCustName] = useState('')
  const [newCustPhone, setNewCustPhone] = useState('')

  // Vente Mode State: Express vs Assisté
  const defaultMode = (activeSector === 'Quincaillerie' || activeSector === 'Électronique' || activeSector === 'Électroménager' || activeSector === 'Téléphonie' || activeSector === 'Matériaux') ? 'assiste' : 'express'
  const [venteMode, setVenteMode] = useState<'express' | 'assiste'>(defaultMode)

  // Item-level Price Negotiation State (Vente Assistée)
  const [negotiatingItem, setNegotiatingItem] = useState<{ product: Product; currentPrice: number; qty: number } | null>(null)
  const [customPrices, setCustomPrices] = useState<Record<string, number>>({}) // productId -> custom price
  const [negotiatedPriceInput, setNegotiatedPriceInput] = useState<string>('')
  const [itemNegotiationModalOpen, setItemNegotiationModalOpen] = useState(false)
  const [aiTipOpen, setAiTipOpen] = useState(true)

  const getItemPrice = (product: Product) => customPrices[product.id] ?? product.price

  const handleStartBarcodeScan = () => {
    setBarcodeScanOpen(true)
    setBarcodeStatus('scanning')
    setScannedProduct(null)

    setTimeout(() => {
      // 80% chance match, 20% no match
      const isMatched = Math.random() > 0.2 && products.length > 0
      if (isMatched) {
        const randomProduct = products[Math.floor(Math.random() * products.length)]
        setScannedProduct(randomProduct)
        setBarcodeStatus('found')

        requestProductForCart(randomProduct, (cart.find((item) => item.product.id === randomProduct.id)?.qty ?? 0) + 1)

        setTimeout(() => {
          setBarcodeScanOpen(false)
        }, 1200)
      } else {
        setBarcodeStatus('not_found')
        setTimeout(() => {
          setBarcodeScanOpen(false)
          // Directly open uncatalogued modal with empty name field
          setUncataloguedName('')
          setUncataloguedPrice('')
          setUncataloguedModalOpen(true)
        }, 900)
      }
    }, 1200)
  }

  // Current active cart
  const activeCart = carts.find((c) => c.id === activeCartId) || carts[0] || { id: 'cart-1', name: 'Panier 1', items: [] }
  const cart = activeCart.items
  const cartLabel = (cartToLabel: Cart) => compactCustomerName(cartToLabel.customerName) ?? cartToLabel.name
  const activeCartLabel = cartLabel(activeCart)

  // Setter helper for active cart items
  const setCart = (action: CartItem[] | ((prev: CartItem[]) => CartItem[])) => {
    setCarts((prevCarts) =>
      prevCarts.map((c) => {
        if (c.id === activeCart.id) {
          const updated = typeof action === 'function' ? action(c.items) : action
          return { ...c, items: updated }
        }
        return c
      })
    )
  }

  const setActiveCartCustomer = (name?: string, phone?: string, customerId?: string) => {
    const normalizedName = name?.trim().replace(/\s+/g, ' ').slice(0, 80)
    setCarts((previous) => previous.map((entry) => entry.id === activeCart.id
      ? {
          ...entry,
          customerId: normalizedName ? customerId : undefined,
          customerName: normalizedName || undefined,
          customerPhone: normalizedName ? phone?.trim().slice(0, 24) || undefined : undefined,
        }
      : entry))
  }

  // Create a new cart (for second client)
  const addCart = () => {
    const nextNum = carts.length + 1
    const newId = `cart-${Date.now()}`
    const newCart: Cart = { id: newId, name: `Panier ${nextNum}`, items: [] }
    setCarts((prev) => [...prev, newCart])
    setActiveCartId(newId)
    return newId
  }

  const filtered = products.filter((p) =>
    p.name.toLowerCase().includes(search.toLowerCase())
  )

  const hasInitialisedStock = (product: Product) => product.tenantCatalogueProduct?.initialStock !== null || !product.tenantCatalogueProduct
  const needsFirstSalePrice = (product: Product) => product.catalogueStatus === 'draft' && (!product.tenantCatalogueProduct || product.tenantCatalogueProduct.sellingPrice === null || product.price <= 0)
  const hasStockAvailable = (product: Product, quantity: number) => !hasInitialisedStock(product) || product.isUncatalogued || quantity <= product.stock

  const setCartProductQuantity = (product: Product, targetQty: number) => {
    if (targetQty < 1) return
    if (!hasStockAvailable(product, targetQty)) {
      showToast?.(`${product.name} est en rupture ou la quantité demandée dépasse le stock disponible.`)
      return
    }
    setCart((previous) => {
      const existing = previous.find((item) => item.product.id === product.id)
      if (existing) return previous.map((item) => item.product.id === product.id ? { ...item, product, qty: targetQty } : item)
      return [...previous, { product, qty: targetQty }]
    })
  }

  const requestProductForCart = (product: Product, targetQty: number, usePicker = false) => {
    if (!hasStockAvailable(product, targetQty)) {
      showToast?.(`${product.name} est en rupture ou la quantité demandée dépasse le stock disponible.`)
      return
    }
    if (needsFirstSalePrice(product)) {
      setFirstSalePrice('')
      setPendingFirstSale({ product, qty: targetQty })
      return
    }
    if (usePicker) {
      openPicker(product)
      return
    }
    setCartProductQuantity(product, targetQty)
  }

  const openPicker = (product: Product) => {
    const existing = cart.find((i) => i.product.id === product.id)
    setPickerQty(existing ? existing.qty : 1)
    setPickerProduct(product)
  }

  const openPickerWithQty = (product: Product, targetQty: number) => {
    requestProductForCart(product, targetQty)
  }

  const confirmPicker = () => {
    if (!pickerProduct) return
    if (hasStockAvailable(pickerProduct, pickerQty)) {
      setCartProductQuantity(pickerProduct, pickerQty)
      setPickerProduct(null)
    } else showToast?.(`${pickerProduct.name} est en rupture ou la quantité demandée dépasse le stock disponible.`)
  }

  const updateQty = (id: string, delta: number) => {
    const item = cart.find((entry) => entry.product.id === id)
    if (!item) return
    const quantity = item.qty + delta
    if (quantity < 1) { setCart((previous) => previous.filter((entry) => entry.product.id !== id)); return }
    setCartProductQuantity(item.product, quantity)
  }

  const rawTotal = cart.reduce((s, i) => s + getItemPrice(i.product) * i.qty, 0)
  const total = Math.max(0, rawTotal - appliedDiscount - appliedCouponDiscount - pointsDiscount)
  const itemCount = cart.reduce((s, i) => s + i.qty, 0)

  // Pending carts calculations
  const pendingCartsWithItems = carts.filter((c) => c.id !== activeCart.id && c.items.length > 0)
  const postCheckoutStockPrompt = postCheckoutStockPrompts[0] ?? null

  const promptForStockInitialisation = (prompts: PostSaleStockPrompt[]) => {
    setPostCheckoutStockPrompts(prompts)
    const first = prompts[0]
    if (first) {
      setPostStockCategory(first.product.category || activeSector)
      setPostStockPrice(String(first.product.price))
      setPostStockQty('')
    }
  }

  const dismissStockInitialisation = () => {
    setPostCheckoutStockPrompts((previous) => {
      const remaining = previous.slice(1)
      const next = remaining[0]
      if (next) {
        setPostStockCategory(next.product.category || activeSector)
        setPostStockPrice(String(next.product.price))
        setPostStockQty('')
      }
      return remaining
    })
  }

  const handleEncaisser = () => {
    if (payMethod === 'credit') {
      setPaymentOpen(false)
      setCartOpen(false)
      if (!selectedDebtorId && creditAccounts.length > 0) {
        setSelectedDebtorId(creditAccounts[0].id)
      }
      setCreditSaleOpen(true)
      return
    }

    const stockPrompts = cart
      .filter((item) => item.product.isUncatalogued || (item.product.catalogueStatus === 'draft' && !hasInitialisedStock(item.product)))
      .map((item) => ({ product: item.product, source: item.product.isUncatalogued ? 'uncatalogued' : 'central' } as PostSaleStockPrompt))

    const stockedItems = cart.filter((item) => !item.product.isUncatalogued && hasInitialisedStock(item.product))
    const stockError = onDeductCatalogueStock(stockedItems)
    if (stockError) { showToast?.(stockError); return }

    // Credit loyalty points to attached customer if present
    if (selectedLoyaltyCustomer) {
      const ptsEarned = Math.floor(total / 1000)
      const updatedPts = Math.max(0, selectedLoyaltyCustomer.pointsBalance + ptsEarned - redeemedPoints)
      const updatedSpent = selectedLoyaltyCustomer.totalSpent + total
      const updatedVisits = selectedLoyaltyCustomer.visitCount + 1
      const updatedTier: 'Bronze' | 'Argent' | 'Or' | 'VIP' =
        updatedSpent >= 250000 ? 'VIP' : updatedSpent >= 150000 ? 'Or' : updatedSpent >= 50000 ? 'Argent' : 'Bronze'

      setSelectedLoyaltyCustomer({
        ...selectedLoyaltyCustomer,
        pointsBalance: updatedPts,
        totalSpent: updatedSpent,
        visitCount: updatedVisits,
        tier: updatedTier,
      })

      showToast?.(`Vente validée ! +${ptsEarned} Pts fidélité crédités à ${selectedLoyaltyCustomer.name} (Solde : ${updatedPts} Pts)`)
    }

    setSuccessText('Vente confirmée !')
    setSuccess(true)
    setTimeout(() => {
      setSuccess(false)
      if (carts.length > 1) {
        const remaining = carts.filter((c) => c.id !== activeCart.id)
        setCarts(remaining)
        setActiveCartId(remaining[0].id)
      } else {
        setCarts([{ id: activeCart.id, name: 'Panier 1', items: [] }])
      }
      setPaymentOpen(false)
      setCartOpen(false)

      if (stockPrompts.length) promptForStockInitialisation(stockPrompts)
    }, 1800)
  }

  if (success) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-4 bg-white animate-in zoom-in-95 duration-200">
        <div
          className="w-20 h-20 rounded-full flex items-center justify-center"
          style={{ backgroundColor: '#ECFDF5' }}
        >
          <CheckCircle size={42} color="#12B76A" />
        </div>
        <div className="text-center">
          <p className="text-xl font-bold text-gray-900">{successText}</p>
          <p className="text-gray-500 mt-1">{total.toLocaleString('fr-FR')} FCFA</p>
          <p className="text-xs text-blue-600 font-semibold mt-2">{activeCartLabel} soldé</p>
        </div>
      </div>
    )
  }

  if (paymentOpen) {
    return (
      <div className="flex flex-col h-full bg-white relative">
        <div className="flex items-center gap-3 px-4 py-4 border-b border-gray-100">
          <Button onClick={() => setPaymentOpen(false)} className="p-2 rounded-xl bg-gray-100" aria-label="Fermer">
            <X size={18} color="#1D2939" />
          </Button>
          <div>
            <h2 className="text-lg font-bold text-gray-900">Encaissement</h2>
            <p className="text-xs text-blue-600 font-medium">{activeCartLabel}</p>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3">
          <div
            className="rounded-2xl p-4 text-white text-center shadow-md"
            style={{ background: 'linear-gradient(135deg, #0050FF, #0040CC)' }}
          >
            <p className="text-sm opacity-80 mb-1">Total à encaisser ({activeCartLabel})</p>
            <p className="text-3xl font-bold">{total.toLocaleString('fr-FR')} FCFA</p>
            <p className="text-sm opacity-70 mt-1">{itemCount} article{itemCount > 1 ? 's' : ''}</p>
          </div>

          <p className="text-sm font-semibold text-gray-500 mt-4">Mode de paiement</p>

          {[
            { key: 'especes', label: 'Espèces', icon: Banknote, desc: 'Paiement en cash' },
            { key: 'mobile', label: 'Mobile Money', icon: Smartphone, desc: 'Orange Money, MTN…' },
            { key: 'mixte', label: 'Paiement mixte', icon: CreditCard, desc: 'Espèces + Mobile' },
            { key: 'credit', label: 'À crédit', icon: UserPlus, desc: 'Compte client · Carnet de dette' },
          ].map(({ key, label, icon: Icon, desc }) => (
            <Button
              key={key}
              onClick={() => {
                setPayMethod(key as typeof payMethod)
                if (key === 'credit') {
                  setPaymentOpen(false)
                  setCartOpen(false)
                  if (!selectedDebtorId && creditAccounts.length > 0) {
                    setSelectedDebtorId(creditAccounts[0].id)
                  }
                  setCreditSaleOpen(true)
                }
              }}
              className={`w-full flex items-center gap-3 p-4 rounded-2xl border-2 transition-all ${payMethod === key
                ? 'border-blue-500 bg-blue-50/70 shadow-sm'
                : 'border-gray-200 bg-white hover:border-gray-300'
                }`}
            >
              <div
                className={`w-10 h-10 rounded-xl flex items-center justify-center ${payMethod === key ? 'bg-blue-500' : 'bg-gray-100'
                  }`}
              >
                <Icon size={20} color={payMethod === key ? '#fff' : '#667085'} />
              </div>
              <div className="text-left">
                <p className={`font-semibold text-sm ${payMethod === key ? 'text-blue-700' : 'text-gray-800'}`}>{label}</p>
                <p className="text-xs text-gray-400">{desc}</p>
              </div>
              {payMethod === key && (
                <CheckCircle size={18} color="#0050FF" className="ml-auto" />
              )}
            </Button>
          ))}
        </div>

        <div className="px-4 pb-6 pt-3 border-t border-gray-100">
          <Button
            onClick={handleEncaisser}
            className="w-full py-4 rounded-2xl text-white text-base font-bold flex items-center justify-center gap-2 active:scale-95 transition-all shadow-md"
            style={{ backgroundColor: payMethod === 'credit' ? '#0050FF' : '#12B76A' }}
          >
            {payMethod === 'credit' ? (
              <>
                <UserPlus size={20} />
                <span>Enregistrer à crédit</span>
              </>
            ) : (
              <>
                <CheckCircle size={20} />
                <span>Encaisser {total.toLocaleString('fr-FR')} FCFA</span>
              </>
            )}
          </Button>
        </div>
      </div>
    )
  }

  if (cartOpen) {
    return (
      <div className="fixed inset-0 z-50 flex flex-col bg-slate-50 font-sans animate-in slide-in-from-bottom duration-200">
        {/* Fullscreen Header with Integrated Customer Attachment Banner */}
        <div className="bg-white border-b border-slate-200/80 px-4 pt-3.5 pb-3 shadow-xs space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Button
                onClick={() => setCartOpen(false)}
                className="w-9 h-9 rounded-2xl bg-slate-100 hover:bg-slate-200 text-slate-700 flex items-center justify-center transition-colors cursor-pointer"
                title="Retour à la caisse"
              >
                <ArrowLeft size={18} />
              </Button>
              <div>
                <div className="flex items-center gap-2">
                  <h2 className="text-base font-extrabold text-slate-900" title={activeCart.customerName}>{activeCartLabel}</h2>
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-extrabold bg-indigo-100 text-indigo-700">
                    {itemCount} article{itemCount > 1 ? 's' : ''}
                  </span>
                </div>
                <p className="text-[10px] text-slate-400 font-medium">Panier encaissement en cours</p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              {cart.length > 0 && (
                <Button
                  onClick={() => setCart([])}
                  className="px-2.5 py-1.5 rounded-xl bg-rose-50 text-rose-600 hover:bg-rose-100 text-xs font-bold transition-colors flex items-center gap-1 cursor-pointer"
                  title="Vider ce panier"
                >
                  <Trash2 size={15} />
                  <span>Vider</span>
                </Button>
              )}
              <Button
                onClick={() => setCartOpen(false)}
                className="p-1.5 rounded-xl text-slate-400 hover:bg-slate-100 transition-colors cursor-pointer" aria-label="Fermer"
              >
                <X size={20} />
              </Button>
            </div>
          </div>


          {/* ── MODAL: RATTACHER CLIENT FIDÈLE AU PANIER ── */}
          {attachCustomerModalOpen && (
            <div
              className="absolute inset-0 z-50 flex items-center justify-center px-4"
              style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(2px)' }}
              onClick={() => setAttachCustomerModalOpen(false)}
            >
              <div
                className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
                onClick={(e) => e.stopPropagation()}
              >
                <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                  <div>
                    <h3 className="font-bold text-gray-900 text-base">Rattacher un Client Fidèle</h3>
                    <p className="text-xs text-purple-600 font-medium">Attribution automatique de points en caisse</p>
                  </div>
                  <Button onClick={() => setAttachCustomerModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                    <X size={18} />
                  </Button>
                </div>

                <div className="space-y-2">
                  <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Membres fidélisés disponibles</p>
                  <div className="space-y-1.5 max-h-48 overflow-y-auto">
                    {INITIAL_CUSTOMERS.map((c) => (
                      <Button
                        key={c.id}
                        onClick={() => {
                          setSelectedLoyaltyCustomer(c)
                          setActiveCartCustomer(c.name, c.phone, c.id)
                          setAttachCustomerModalOpen(false)
                          showToast?.(`Client ${c.name} rattaché au panier (${c.pointsBalance} Pts) !`)
                        }}
                        className={`w-full p-3 rounded-2xl border text-left transition-all flex items-center justify-between ${selectedLoyaltyCustomer?.id === c.id ? 'border-purple-600 bg-purple-50/60' : 'border-gray-100 hover:bg-gray-50'
                          }`}
                      >
                        <div>
                          <p className="text-xs font-bold text-gray-900">{c.name}</p>
                          <p className="text-[10px] text-gray-400">📞 +237 {c.phone} · {c.tier}</p>
                        </div>
                        <span className="text-xs font-bold text-purple-700">{c.pointsBalance} Pts</span>
                      </Button>
                    ))}
                  </div>
                </div>

                <div className="pt-2 border-t border-gray-100 space-y-2">
                  <p className="text-xs font-bold text-gray-700">Ou créer rapidement un nouveau membre :</p>
                  <div className="flex gap-2">
                    <Input
                      type="text"
                      value={newCustName}
                      onChange={(e) => setNewCustName(e.target.value)}
                      placeholder="Nom client"
                      className="flex-1 bg-gray-100 rounded-xl px-3 py-2 text-xs font-bold text-gray-900 outline-none"
                    />
                    <Input
                      type="text"
                      value={newCustPhone}
                      onChange={(e) => setNewCustPhone(e.target.value)}
                      placeholder="N° Tél"
                      className="w-24 bg-gray-100 rounded-xl px-3 py-2 text-xs font-bold text-gray-900 outline-none"
                    />
                  </div>
                  <Button
                    disabled={!newCustName.trim()}
                    onClick={() => {
                      const newC: CustomerLoyalty = {
                        id: `cust-${Date.now()}`,
                        name: newCustName.trim(),
                        phone: newCustPhone.trim() || '690000000',
                        pointsBalance: 0,
                        totalSpent: 0,
                        visitCount: 1,
                        tier: 'Bronze',
                        lastVisitDate: "Aujourd'hui",
                      }
                      setSelectedLoyaltyCustomer(newC)
                      setActiveCartCustomer(newC.name, newC.phone, newC.id)
                      setAttachCustomerModalOpen(false)
                      showToast?.(`Nouveau client ${newC.name} créé et rattaché !`)
                    }}
                    className="w-full py-2.5 rounded-xl bg-purple-600 text-white font-bold text-xs hover:bg-purple-700 transition-colors shadow-xs disabled:opacity-40"
                  >
                    Créer & Rattacher au panier
                  </Button>
                </div>
              </div>
            </div>
          )}



          {/* Customer Attachment Banner (Header Direct Inline Name Input + Loyalty Member Button) */}
          <div className="p-3 bg-gradient-to-r from-purple-900 via-indigo-950 to-slate-900 text-white rounded-2xl shadow-sm border border-purple-800/60 space-y-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-xl bg-purple-500/30 border border-purple-400/40 text-purple-200 flex items-center justify-center font-bold text-xs">
                  {selectedLoyaltyCustomer ? selectedLoyaltyCustomer.name[0].toUpperCase() : <UserCheck size={14} />}
                </div>
                <div>
                  {/* <p className="text-[10px] font-extrabold text-purple-300 uppercase tracking-wider">Attribution Client & Fidélisation</p> */}
                  {selectedLoyaltyCustomer ? (
                    <p className="text-xs font-bold text-white flex items-center gap-1.5">
                      {selectedLoyaltyCustomer.name}
                      <span className="text-[9px] font-extrabold px-1.5 py-0.2 rounded-full bg-purple-500/40 text-purple-200 border border-purple-400/30">
                        {selectedLoyaltyCustomer.pointsBalance} Pts · {selectedLoyaltyCustomer.tier}
                      </span>
                    </p>
                  ) : (
                    <div className="flex items-center gap-2 bg-white/10 backdrop-blur-md rounded-xl p-1.5 border border-white/15">
                      <User size={14} className="text-purple-300 ml-1 flex-shrink-0" />
                      <Input
                        type="text"
                        value={activeCart.customerName || ''}
                        onChange={(e) => {
                          setActiveCartCustomer(e.target.value)
                        }}
                        placeholder="Nom direct du client (ex: M. Etoa, Hôtel Sawa...)"
                        className="flex-1 bg-transparent text-xs font-bold text-white placeholder-slate-400 outline-none"
                      />
                      {activeCart.customerName && (
                        <Button
                          onClick={() => {
                            setActiveCartCustomer()
                          }}
                          className="p-1 rounded-lg text-slate-400 hover:text-white transition-colors"
                          title="Effacer le nom du client"
                        >
                          <X size={13} />
                        </Button>
                      )}
                    </div>


                  )}
                </div>
              </div>

              <Button
                onClick={() => setAttachCustomerModalOpen(true)}
                className="px-2.5 py-1.5 rounded-xl bg-purple-600 hover:bg-purple-700 text-white font-extrabold text-[11px] shadow-xs active:scale-95 transition-transform flex items-center gap-1 cursor-pointer"
              >
                <User size={13} />
                <span>{selectedLoyaltyCustomer ? 'Changer' : 'Client Fidèle'}</span>
              </Button>
            </div>


          </div>

          {/* Multi-cart Switcher Sub-Bar */}
          <div className="flex items-center justify-between pt-0.5">
            <div className="flex items-center gap-1.5 overflow-x-auto scrollbar-hide py-0.5">
              {carts.map((c) => {
                const isActive = c.id === activeCart.id
                const cCount = c.items.reduce((s, i) => s + i.qty, 0)
                return (
                  <Button
                    key={c.id}
                    onClick={() => setActiveCartId(c.id)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-extrabold whitespace-nowrap transition-all cursor-pointer ${isActive
                      ? 'bg-indigo-600 text-white shadow-xs'
                      : cCount > 0
                        ? 'bg-amber-100 text-amber-900 border border-amber-300'
                        : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                      }`}
                  >
                    <span title={c.customerName}>{cartLabel(c)} {cCount > 0 ? `(${cCount})` : ''}</span>
                  </Button>
                )
              })}
            </div>
            <Button
              onClick={() => {
                addCart()
              }}
              className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-amber-500 hover:bg-amber-600 text-white text-xs font-extrabold shadow-2xs active:scale-95 transition-all flex-shrink-0 ml-2 cursor-pointer"
            >
              <Clock size={13} /> + 2<sup>e</sup> Client
            </Button>
          </div>
        </div>

        {/* Cart Items List Area */}
        <div className="flex-1 overflow-y-auto px-4 py-3 space-y-2 animate-cascade stagger-1">
          {cart.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full gap-3 text-slate-400 py-16">
              <div className="w-16 h-16 rounded-3xl bg-slate-100 flex items-center justify-center text-slate-400">
                <ShoppingCart size={32} strokeWidth={1.5} />
              </div>
              <p className="text-sm font-bold text-slate-700">Ce panier est vide</p>
              <p className="text-xs text-slate-400 text-center max-w-[240px]">
                Sélectionnez des produits dans le catalogue pour composer la vente.
              </p>
              <Button
                onClick={() => setCartOpen(false)}
                className="mt-2 px-4 py-2 rounded-xl bg-indigo-600 text-white text-xs font-extrabold shadow-xs"
              >
                Retour au Catalogue
              </Button>
            </div>
          ) : (
            <>
              {/* AI Assistant Commercial Widget (Vente Assistée) */}
              {venteMode === 'assiste' && aiTipOpen && (
                <div className="mb-3 p-3.5 bg-indigo-50/80 border border-indigo-100 rounded-2xl flex items-start gap-2.5 text-xs text-indigo-900 shadow-2xs animate-cascade stagger-1">
                  <Bot size={18} className="text-indigo-600 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <p className="font-extrabold text-gray-900 flex items-center gap-1.5">
                      Assistant IA Commercial
                      <span className="text-[9px] bg-indigo-200 text-indigo-800 font-extrabold px-1.5 py-0.2 rounded-full">Pro</span>
                    </p>
                    <p className="text-[11px] text-indigo-700 mt-0.5 leading-relaxed">
                      💡 <span className="font-bold">Marge globale : 28%</span>. Une remise maximale de <span className="font-bold">{Math.round(total * 0.08).toLocaleString('fr-FR')} FCFA</span> est conseillée sans dégrader votre rentabilité.
                    </p>
                  </div>
                  <Button onClick={() => setAiTipOpen(false)} className="text-indigo-400 hover:text-indigo-600" aria-label="Fermer">
                    <X size={14} />
                  </Button>
                </div>
              )}

              {cart.map((item, idx) => {
                const itemUnitPrice = getItemPrice(item.product)
                const isNegotiated = customPrices[item.product.id] !== undefined
                const staggerClass = `stagger-${Math.min((idx % 8) + 1, 10)}`
                return (
                  <div
                    key={item.product.id}
                    className={`bg-white border border-slate-100 rounded-2xl p-3 shadow-2xs transition-all hover:border-indigo-100 animate-cascade ${staggerClass}`}
                  >
                    <div className="flex items-start gap-3">
                      {showCatalogueImages && <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl border border-slate-100 bg-slate-50 p-1.5"><ProductThumbnail product={item.product} className="h-full w-full" /></div>}
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-extrabold leading-tight text-slate-900 break-words">{item.product.name}</p>
                        <p className="mt-0.5 text-[10px] font-semibold text-indigo-600">{productReference(item.product)}</p>
                        <div className="mt-1 flex flex-wrap items-center gap-2">
                          <ProductStockBadge product={item.product} />
                          <p className="text-xs font-bold text-indigo-600">{itemUnitPrice.toLocaleString('fr-FR')} FCFA / unité</p>
                        {isNegotiated && (
                          <span className="px-1.5 py-0.2 rounded text-[9px] font-extrabold bg-purple-100 text-purple-700">Négocié</span>
                        )}
                        </div>
                      </div>
                    </div>

                    <div className="mt-3 flex items-center justify-between gap-2 border-t border-slate-100 pt-2.5">
                      <div>
                        <Button
                          onClick={() => {
                            setNegotiatingItem({ product: item.product, currentPrice: itemUnitPrice, qty: item.qty })
                            setNegotiatedPriceInput(String(itemUnitPrice))
                            setItemNegotiationModalOpen(true)
                            if (venteMode === 'express') {
                              setVenteMode('assiste')
                              showToast?.("Basculement automatique en Mode Vente Assistée pour négociation")
                            }
                          }}
                          className="px-2 py-0.5 rounded-lg bg-purple-100 text-purple-700 text-[10px] font-extrabold hover:bg-purple-200 transition-colors cursor-pointer"
                        >
                          🏷️ Négocier
                        </Button>
                      </div>

                    <div className="flex items-center gap-1.5 shrink-0">
                      <Button
                        onClick={() => updateQty(item.product.id, -1)}
                        className="w-7 h-7 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 flex items-center justify-center font-bold transition-colors cursor-pointer" aria-label="Retirer"
                      >
                        <Minus size={13} />
                      </Button>
                      <span className="w-5 text-center text-xs font-extrabold text-slate-900">{item.qty}</span>
                      <Button
                        onClick={() => updateQty(item.product.id, 1)}
                        className="w-7 h-7 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white flex items-center justify-center font-bold transition-colors shadow-xs cursor-pointer" aria-label="Ajouter"
                      >
                        <Plus size={13} />
                      </Button>
                    </div>

                    <p className="text-sm font-extrabold text-slate-900 text-right shrink-0">
                      {(itemUnitPrice * item.qty).toLocaleString('fr-FR')} <span className="text-[10px] font-normal text-slate-400">F</span>
                    </p>
                    </div>
                  </div>
                )
              })}
            </>
          )}
        </div>

        {/* Bottom Checkout & Action Bar */}
        {
          cart.length > 0 && (
            <div className="bg-white border-t border-slate-200/80 px-4 pb-6 pt-3 space-y-3 shadow-lg font-sans">
              {/* Loyalty Points Conversion CTA */}
              {selectedLoyaltyCustomer && selectedLoyaltyCustomer.pointsBalance >= 50 && (
                <Button
                  onClick={() => {
                    const ptsToUse = 50
                    const valDisc = ptsToUse * 10
                    setRedeemedPoints(ptsToUse)
                    setPointsDiscount(valDisc)
                    showToast?.(`50 Points convertis en -${valDisc.toLocaleString('fr-FR')} FCFA de remise !`)
                  }}
                  className="w-full py-2 rounded-xl bg-purple-100 border border-purple-200 text-purple-800 text-xs font-bold hover:bg-purple-200 transition-colors flex items-center justify-center gap-1.5 shadow-2xs cursor-pointer"
                >
                  <Gift size={14} />
                  <span>Convertir 50 Pts ➔ -500 FCFA de remise</span>
                </Button>
              )}

              {/* Coupon Code input */}
              <div className="flex gap-2">
                <Input
                  type="text"
                  value={couponInput}
                  onChange={(e) => setCouponInput(e.target.value.toUpperCase())}
                  placeholder="Code promo (ex: BIENVENUE10, VIP2000)"
                  className="flex-1 bg-slate-100 rounded-xl px-3 py-2 text-xs font-bold text-slate-900 uppercase outline-none focus:ring-2 focus:ring-indigo-500/20"
                />
                <Button
                  onClick={() => {
                    const code = couponInput.trim()
                    if (code === 'BIENVENUE10') {
                      const disc = Math.round((rawTotal * 10) / 100)
                      setAppliedCouponDiscount(disc)
                      setAppliedCouponCode(code)
                      showToast?.(`Code ${code} appliqué : -10% (${disc.toLocaleString('fr-FR')} F)`)
                    } else if (code === 'VIP2000') {
                      setAppliedCouponDiscount(2000)
                      setAppliedCouponCode(code)
                      showToast?.(`Code ${code} appliqué : -2 000 FCFA`)
                    } else {
                      showToast?.("Code promo non valide ou expiré.")
                    }
                  }}
                  className="px-3 py-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white font-bold text-xs active:scale-95 transition-transform cursor-pointer"
                >
                  Appliquer
                </Button>
              </div>

              {appliedCouponDiscount > 0 && (
                <div className="flex justify-between items-center text-xs font-bold text-purple-700 bg-purple-50 p-2 rounded-xl border border-purple-100">
                  <span>Code {appliedCouponCode} appliqué :</span>
                  <span>-{appliedCouponDiscount.toLocaleString('fr-FR')} FCFA</span>
                </div>
              )}

              {/* Summary Line */}
              <div className="flex items-center justify-between pt-1 border-t border-slate-100">
                <div>
                  <span className="text-slate-500 text-xs font-semibold block">Total Net ({activeCartLabel})</span>
                  {(selectedLoyaltyCustomer || devisClientName) && (
                    <span className="text-[10px] font-extrabold text-purple-700 block">
                      Client : {selectedLoyaltyCustomer ? selectedLoyaltyCustomer.name : devisClientName}
                    </span>
                  )}
                </div>
                <span className="text-xl font-extrabold text-slate-900">{total.toLocaleString('fr-FR')} <span className="text-xs font-bold text-slate-400">FCFA</span></span>
              </div>

              {/* Action Buttons */}
              <div className="flex gap-2 pt-1">
                <Button
                  onClick={() => {
                    addCart()
                    showToast?.("Nouveau client en attente ajouté")
                  }}
                  className="flex-1 py-3.5 px-3 rounded-2xl bg-amber-50 border border-amber-200 text-amber-800 text-xs font-bold flex items-center justify-center gap-1.5 active:scale-95 transition-transform cursor-pointer"
                >
                  <Clock size={16} /> Servir 2<sup>e</sup> client
                </Button>
                <Button
                  onClick={() => setPaymentOpen(true)}
                  className="flex-1 py-3.5 px-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-extrabold flex items-center justify-center gap-1.5 active:scale-95 transition-all shadow-md cursor-pointer"
                >
                  <span>Encaisser</span>
                  <ArrowUpRight size={18} />
                </Button>
              </div>
            </div>
          )
        }
      </div >
    )
  }

  return (
    <div className="lk-sale flex flex-col h-full">
      {/* Top Controls: Vente Mode, Multi-cart & Search */}
      <div className="lk-sale-top bg-white px-4 pt-3 pb-3 border-b border-gray-100">

        {/* Multi-cart Pill Selector Bar */}
        <div className="flex items-center gap-1.5 overflow-x-auto pb-2 scrollbar-hide">
          {carts.map((c) => {
            const isActive = c.id === activeCart.id
            const cCount = c.items.reduce((s, i) => s + i.qty, 0)
            const cTotal = c.items.reduce((s, i) => s + i.product.price * i.qty, 0)
            return (
              <Button
                key={c.id}
                onClick={() => setActiveCartId(c.id)}
                className={`lk-sale-cart-tab flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold transition-all whitespace-nowrap border ${isActive
                  ? 'bg-blue-600 text-white border-blue-600 shadow-sm'
                  : cCount > 0
                    ? 'bg-amber-50 text-amber-800 border-amber-300'
                    : 'bg-gray-100 text-gray-500 border-gray-200'
                  }`}
              >
                {cCount > 0 && !isActive && (
                  <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
                )}
                  <span title={c.customerName}>{cartLabel(c)}</span>
                {cCount > 0 && (
                  <span
                    className={`px-1.5 py-0.5 rounded-md text-[10px] ${isActive ? 'bg-white/20 text-white font-bold' : 'bg-amber-200 text-amber-900 font-bold'
                      }`}
                  >
                    {cCount} art. {cTotal > 0 ? `• ${cTotal.toLocaleString('fr-FR')} F` : ''}
                  </span>
                )}
              </Button>
            )
          })}

          {/* Quick add 2nd client button */}
          <Button
            onClick={addCart}
            className="lk-sale-new-cart flex items-center gap-1 px-2.5 py-1.5 rounded-xl text-xs font-semibold bg-blue-50 text-blue-700 border border-blue-200 hover:bg-blue-100 transition-all whitespace-nowrap active:scale-95"
            title="Ouvrir un nouveau panier pour un autre client"
          >
            <UserPlus size={14} />
            <span>+ 2<sup>e</sup> client</span>
          </Button>
        </div>

        {/* Search */}
        <div className="flex gap-2 mt-1">
          <div className="lk-sale-search flex-1 flex items-center gap-2 bg-gray-100 rounded-xl px-3 py-2.5">
            <Search size={16} color="#98A2B3" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Rechercher un produit..."
              className="flex-1 bg-transparent text-sm text-gray-700 placeholder-gray-400 outline-none"
            />
          </div>
          <Button
            onClick={handleStartBarcodeScan}
            className="lk-stock-new-product  w-11  rounded-xl flex items-center justify-center active:scale-95 transition-transform"
            title="Scanner un code-barres"
          >
            <QrCode size={20} color="white" />
          </Button>
        </div>
      </div>

      {/* Produits rapides */}
      <div className="lk-sale-products flex-1 overflow-y-auto px-4 py-3">
        {/* On-hold notification bar if pending carts exist */}
        {pendingCartsWithItems.length > 0 && (
          <div className="mb-3 bg-amber-50 border border-amber-200 rounded-2xl p-2.5 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 rounded-xl bg-amber-500 text-white flex items-center justify-center font-bold text-xs">
                <Clock size={14} />
              </div>
              <div>
                <p className="text-xs font-bold text-amber-900">
                  {pendingCartsWithItems.length} client{pendingCartsWithItems.length > 1 ? 's' : ''} en attente
                </p>
                <p className="text-[10px] text-amber-700">
                  {pendingCartsWithItems.map((c) => `${cartLabel(c)} (${c.items.reduce((s, i) => s + i.product.price * i.qty, 0).toLocaleString('fr-FR')} F)`).join(', ')}
                </p>
              </div>
            </div>
            <Button
              onClick={() => setActiveCartId(pendingCartsWithItems[0].id)}
              className="px-2.5 py-1 rounded-xl bg-amber-500 text-white text-xs font-bold active:scale-95 transition-transform"
            >
              Reprendre
            </Button>
          </div>
        )}

        <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-3">
          {search ? `Résultats (${filtered.length})` : `Produits pour ${activeCartLabel}`}
        </p>
        <div className={catalogueDisplay === 'grid' ? 'grid grid-cols-2 gap-3' : 'space-y-2'}>
          {/* Produit hors catalogue */}
          <Button
            onClick={() => setUncataloguedModalOpen(true)}
            className={`bg-gray-50 rounded-2xl p-3 border-2 border-dashed border-gray-200 flex ${catalogueDisplay === 'grid' ? 'flex-col items-center justify-center min-h-[100px]' : 'items-center justify-center min-h-16'} gap-1 active:scale-95 transition-transform hover:border-blue-300 hover:bg-blue-50/30 animate-cascade stagger-2`}
          >
            <Plus size={22} color="#0050FF" />
            <span className="text-xs text-blue-700 font-bold text-center">Produit hors catalogue</span>
          </Button>

          {filtered.map((product, idx) => {
            const inCart = cart.find((i) => i.product.id === product.id)
            const currentPrice = getItemPrice(product)
            const isCustom = customPrices[product.id] !== undefined
            const staggerClass = `stagger-${Math.min((idx % 8) + 3, 10)}`
            const addProductFromCard = () => {
              if (venteMode === 'express') {
                openPickerWithQty(product, (inCart?.qty || 0) + 1)
              } else {
                requestProductForCart(product, inCart?.qty || 1, true)
              }
            }
            return (
              <div
                key={product.id}
                onClick={addProductFromCard}
                className={`lk-sale-product bg-white rounded-2xl p-3 text-left border active:scale-95 transition-all hover:shadow-sm relative cursor-pointer flex ${catalogueDisplay === 'grid' ? `flex-col justify-between ${showCatalogueImages ? 'min-h-[236px]' : 'min-h-[178px]'}` : 'items-center gap-3 min-h-[96px]'} animate-cascade ${staggerClass}`}
                style={{ borderColor: inCart ? '#0050FF' : '#F2F4F7' }}
              >
                {inCart && (
                  <span
                    className="absolute top-2 right-2 w-5 h-5 rounded-full text-white text-[10px] font-bold flex items-center justify-center shadow-2xs"
                    style={{ backgroundColor: '#0050FF' }}
                  >
                    {inCart.qty}
                  </span>
                )}
                <div className={`flex ${catalogueDisplay === 'grid' ? 'flex-col gap-2' : 'items-center gap-3 flex-1 min-w-0'}`}>
                  {showCatalogueImages && <div className={`flex shrink-0 items-center justify-center rounded-xl border border-slate-100 bg-slate-50 ${catalogueDisplay === 'grid' ? 'h-24 w-full p-2' : 'h-16 w-16 p-1.5'}`}><ProductThumbnail product={product} className="h-full w-full" /></div>}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-gray-900 leading-tight break-words">{product.name}</p>
                        <p className="mt-0.5 truncate text-[10px] font-semibold text-blue-600" title={productReference(product)}>{productReference(product)}</p>
                      </div>
                    </div>
                  <div className={catalogueDisplay === 'list' ? 'mt-1' : 'mt-1.5'}>
                  {needsFirstSalePrice(product) ? (
                    <p className="text-xs font-bold text-amber-700">Prix à saisir à la première vente</p>
                  ) : (
                    <p className="text-base font-bold" style={{ color: isCustom ? '#7C3AED' : '#0050FF' }}>
                      {currentPrice.toLocaleString('fr-FR')} <span className="text-xs font-normal text-gray-400">FCFA</span>
                      {isCustom && <span className="text-[9px] font-bold block text-purple-600">Négocié</span>}
                    </p>
                  )}
                  <div className="mt-0.5 flex items-center gap-1.5 text-[10px] text-gray-400">
                    {catalogueDisplay === 'list' && <ProductStockBadge product={product} />}
                    <span>{product.isUncatalogued ? 'Article hors catalogue' : hasInitialisedStock(product) ? `Stock : ${product.stock} · ${product.category}` : 'Stock à initialiser après la vente'}</span>
                  </div>
                </div>
                  </div>
                </div>

                {!inCart && (
                  <div className={`flex items-center ${catalogueDisplay === 'grid' ? 'justify-between border-t border-gray-100 pt-2' : 'shrink-0'} gap-2`} onClick={(event) => event.stopPropagation()}>
                    {catalogueDisplay === 'grid' && <ProductStockBadge product={product} />}
                    <Button onClick={addProductFromCard} className={`${catalogueDisplay === 'grid' ? 'h-9 w-9' : 'min-h-10 px-3'} rounded-xl bg-blue-600 text-white flex items-center justify-center gap-1.5 shadow-sm active:scale-95`} aria-label={`Ajouter ${product.name} au panier`}>
                      <ShoppingCart size={16} />
                      {catalogueDisplay === 'list' && <span className="text-[11px] font-bold">Ajouter</span>}
                    </Button>
                  </div>
                )}

                {/* Direct 1-tap Stepper in Vente Express Mode */}
                {venteMode === 'express' && inCart && (
                  <div className="mt-2 pt-2 border-t border-gray-100 flex items-center justify-between" onClick={(e) => e.stopPropagation()}>
                    <Button
                      onClick={() => updateQty(product.id, -1)}
                      className="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-800 font-bold text-xs flex items-center justify-center active:scale-95"
                    >
                      -
                    </Button>
                    <span className="text-xs font-bold text-blue-700">{inCart.qty}</span>
                    <Button
                      onClick={() => updateQty(product.id, 1)}
                      className="w-7 h-7 rounded-lg bg-blue-600 text-white font-bold text-xs flex items-center justify-center active:scale-95 shadow-2xs"
                    >
                      +
                    </Button>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>

      {/* Cart bottom bar */}
      {cart.length > 0 && (
        <div className="lk-sale-cart-summary px-4 pb-6 pt-3 bg-white border-t border-gray-100">
          <Button
            onClick={() => setCartOpen(true)}
            className="lk-sale-cart-cta w-full flex items-center justify-between py-4 px-5 rounded-2xl text-white active:scale-95 transition-transform"
          >
            <div className="flex items-center gap-2">
              <ShoppingCart size={20} />
              <div className="text-left"><span className="font-extrabold block">VOIR LE PANIER</span><span className="text-xs opacity-90">{itemCount} article{itemCount > 1 ? 's' : ''} · {activeCartLabel}</span></div>
            </div>
            <div className="flex items-center gap-2">
              <span className="font-bold text-lg">{total.toLocaleString('fr-FR')} FCFA</span>
              <ChevronRight size={18} />
            </div>
          </Button>
        </div>
      )}

      {/* ── Product picker popup ── */}
      {pickerProduct && (
        <div
          className="absolute inset-0 flex items-end justify-center z-50"
          style={{ backgroundColor: 'rgba(0,0,0,0.45)', backdropFilter: 'blur(2px)' }}
          onClick={() => setPickerProduct(null)}
        >
          <div
            className="w-full bg-white rounded-t-3xl px-5 pt-5 pb-8 space-y-5"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Drag handle */}
            <div className="w-10 h-1 bg-gray-200 rounded-full mx-auto" />

            {/* Product info */}
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 rounded-2xl flex items-center justify-center text-4xl bg-gray-50 flex-shrink-0">
                {pickerProduct.emoji}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-base font-bold text-gray-900 leading-tight">{pickerProduct.name}</p>
                <p className="text-xs text-gray-400 mt-0.5">{pickerProduct.category} · {hasInitialisedStock(pickerProduct) ? `Stock : ${pickerProduct.stock}` : 'Stock à initialiser après la vente'}</p>
                {pickerProduct.alert && (
                  <div className="mt-1.5">
                    <AlertBadge level={pickerProduct.alert} stock={pickerProduct.stock} />
                  </div>
                )}
              </div>
              <div className="text-right flex-shrink-0">
                <p className="text-lg font-bold" style={{ color: '#0050FF' }}>
                  {pickerProduct.price.toLocaleString('fr-FR')}
                </p>
                <p className="text-xs text-gray-400">FCFA / unité</p>
              </div>
            </div>

            {/* Qty row */}
            <div className="flex items-center justify-between bg-gray-50 rounded-2xl px-5 py-4">
              <Button
                onClick={() => setPickerQty((q) => Math.max(1, q - 1))}
                className="w-11 h-11 rounded-xl border-2 border-gray-200 bg-white flex items-center justify-center active:scale-90 transition-transform" aria-label="Retirer"
              >
                <Minus size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <span className="text-3xl font-bold text-gray-900">{pickerQty}</span>
                <p className="text-xs text-gray-400 mt-0.5">unité{pickerQty > 1 ? 's' : ''}</p>
              </div>
              <Button
                onClick={() => setPickerQty((q) => hasInitialisedStock(pickerProduct) ? Math.min(pickerProduct.stock, q + 1) : q + 1)}
                className="w-11 h-11 rounded-xl flex items-center justify-center text-white active:scale-90 transition-transform"
                style={{ backgroundColor: '#0050FF' }} aria-label="Ajouter"
              >
                <Plus size={18} />
              </Button>
            </div>

            {/* Total + CTA */}
            <div className="flex items-center gap-3">
              <div className="flex-1 bg-blue-50 rounded-2xl px-4 py-3 text-center">
                <p className="text-xs text-blue-500 font-medium">Total ligne</p>
                <p className="text-lg font-bold" style={{ color: '#0050FF' }}>
                  {(pickerProduct.price * pickerQty).toLocaleString('fr-FR')} FCFA
                </p>
              </div>
              <Button
                onClick={confirmPicker}
                className="flex-1 py-4 rounded-2xl text-white font-bold text-sm flex items-center justify-center gap-2 active:scale-95 transition-transform"
                style={{ backgroundColor: '#0050FF' }}
              >
                <ShoppingCart size={18} />
                {cart.find((i) => i.product.id === pickerProduct.id) ? 'Mettre à jour' : 'Ajouter au panier'}
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* ── MODAL 1: Vente à crédit ── */}
      {creditSaleOpen && (
        <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200">
          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100">
            <Button
              onClick={() => {
                setCreditSaleOpen(false)
                setPaymentOpen(true)
              }}
              className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
            >
              <ChevronLeft size={18} color="#1D2939" />
            </Button>
            <div className="text-center">
              <h2 className="text-lg font-bold text-gray-900">Vente à crédit</h2>
              <p className="text-xs text-blue-600 font-medium">{activeCartLabel}</p>
            </div>
            <div className="w-8" />
          </div>

          <div className="p-4 space-y-4 flex-1 flex flex-col justify-between">
            <div className="space-y-4">
              {/* Blue Gradient Header */}
              <div
                className="rounded-2xl p-4 text-white text-center shadow-md"
                style={{ background: 'linear-gradient(135deg, #0050FF, #0040CC)' }}
              >
                <p className="text-xs opacity-80 mb-1 font-semibold uppercase tracking-wider">Montant total à créditer</p>
                <p className="text-3xl font-bold">{total.toLocaleString('fr-FR')} FCFA</p>
                <p className="text-xs opacity-75 mt-1">{itemCount} article{itemCount > 1 ? 's' : ''} ({cart.map(i => i.product.name).join(', ')})</p>
              </div>

              {/* Toggle Existing / New */}
              <div className="flex bg-gray-100 p-1 rounded-xl">
                <Button
                  onClick={() => setIsNewDebtor(false)}
                  className={`flex-1 py-2 rounded-lg text-xs font-bold transition-all ${!isNewDebtor ? 'bg-white text-blue-600 shadow-sm' : 'text-gray-500'}`}
                >
                  Client existant ({creditAccounts.length})
                </Button>
                <Button
                  onClick={() => setIsNewDebtor(true)}
                  className={`flex-1 py-2 rounded-lg text-xs font-bold transition-all ${isNewDebtor ? 'bg-white text-blue-600 shadow-sm' : 'text-gray-500'}`}
                >
                  + Nouveau client
                </Button>
              </div>

              {!isNewDebtor ? (
                <div className="space-y-2">
                  <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Sélectionnez le compte client</p>
                  <div className="divide-y divide-gray-100 border border-gray-100 rounded-2xl overflow-hidden bg-white max-h-56 overflow-y-auto">
                    {creditAccounts.map((acc) => {
                      const bal = getAccountBalance(acc)
                      const isSelected = selectedDebtorId === acc.id
                      return (
                        <Button
                          key={acc.id}
                          onClick={() => setSelectedDebtorId(acc.id)}
                          className={`w-full flex items-center justify-between p-3.5 text-left transition-all ${isSelected ? 'bg-blue-50/70 border-l-4 border-blue-600' : 'hover:bg-gray-50'}`}
                        >
                          <div>
                            <p className="text-sm font-bold text-gray-900">{acc.name}</p>
                            <p className="text-[11px] text-gray-400">{acc.phone ? `+237 ${acc.phone}` : 'Pas de numéro'}</p>
                          </div>
                          <div className="text-right">
                            <span className={`text-xs font-bold px-2.5 py-1 rounded-full ${bal > 0 ? 'bg-red-50 text-red-600' : 'bg-green-50 text-green-600'}`}>
                              {bal > 0 ? `${bal.toLocaleString('fr-FR')} F dû` : 'Soldé'}
                            </span>
                          </div>
                        </Button>
                      )
                    })}
                  </div>
                </div>
              ) : (
                <div className="space-y-3 bg-gray-50 p-4 rounded-2xl border border-gray-100">
                  <div>
                    <label className="text-xs font-bold text-gray-700">Nom du client <span className="text-red-500">*</span></label>
                    <Input
                      type="text"
                      value={newDebtorName}
                      onChange={(e) => setNewDebtorName(e.target.value)}
                      placeholder="Ex: Tante Marie"
                      className="w-full mt-1 bg-white rounded-xl px-3 py-3 text-sm font-semibold outline-none border border-gray-200"
                    />
                  </div>
                  <div>
                    <label className="text-xs font-bold text-gray-700">Numéro de téléphone (optionnel)</label>
                    <Input
                      type="tel"
                      value={newDebtorPhone}
                      onChange={(e) => setNewDebtorPhone(e.target.value)}
                      placeholder="Ex: 699123456"
                      className="w-full mt-1 bg-white rounded-xl px-3 py-3 text-sm font-semibold outline-none border border-gray-200"
                    />
                    <p className="text-[10px] text-gray-400 mt-1 italic">💬 Sert uniquement aux rappels de courtoisie par WhatsApp.</p>
                  </div>
                </div>
              )}
            </div>

            <Button
              disabled={!isNewDebtor ? !selectedDebtorId : !newDebtorName.trim()}
              onClick={() => {
                const saleDesc = cart.map(i => `${i.product.name} (x${i.qty})`).join(' · ')
                const newMov: CreditMovement = {
                  id: `m-${Date.now()}`,
                  date: new Date().toLocaleDateString('fr-FR'),
                  type: 'sale',
                  amount: total,
                  description: saleDesc,
                }

                if (isNewDebtor) {
                  const newAcc: CreditAccount = {
                    id: `acc-${Date.now()}`,
                    name: newDebtorName.trim(),
                    phone: newDebtorPhone.trim(),
                    movements: [newMov],
                  }
                  setCreditAccounts(prev => [...prev, newAcc])
                } else {
                  setCreditAccounts(prev => prev.map(acc => acc.id === selectedDebtorId ? { ...acc, movements: [...acc.movements, newMov] } : acc))
                }

                const stockPrompts = cart
                  .filter((item) => item.product.isUncatalogued || (item.product.catalogueStatus === 'draft' && !hasInitialisedStock(item.product)))
                  .map((item) => ({ product: item.product, source: item.product.isUncatalogued ? 'uncatalogued' : 'central' } as PostSaleStockPrompt))

                const stockedItems = cart.filter((item) => !item.product.isUncatalogued && hasInitialisedStock(item.product))
                const stockError = onDeductCatalogueStock(stockedItems)
                if (stockError) { showToast?.(stockError); return }

                setCreditSaleOpen(false)
                setSuccessText('Vente à crédit enregistrée !')
                setSuccess(true)

                setTimeout(() => {
                  setSuccess(false)
                  if (carts.length > 1) {
                    const remaining = carts.filter((c) => c.id !== activeCart.id)
                    setCarts(remaining)
                    setActiveCartId(remaining[0].id)
                  } else {
                    setCarts([{ id: activeCart.id, name: 'Panier 1', items: [] }])
                  }
                  setPaymentOpen(false)
                  setCartOpen(false)

                  if (stockPrompts.length) promptForStockInitialisation(stockPrompts)
                }, 1800)
              }}
              className="w-full py-4 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-transform disabled:opacity-40 shadow-lg shadow-blue-500/25"
            >
              Confirmer la vente à crédit
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL: premier prix d’une référence interne ── */}
      {pendingFirstSale && (
        <div className="absolute inset-0 z-50 flex items-center justify-center px-4" style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}>
          <div className="w-full rounded-3xl bg-white p-5 shadow-2xl animate-in zoom-in-95 duration-200">
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div>
                <p className="text-[10px] font-bold uppercase tracking-wider text-amber-700">Catalogue interne</p>
                <h3 className="text-base font-bold text-gray-900">Définir le prix de première vente</h3>
              </div>
              <Button onClick={() => setPendingFirstSale(null)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer"><X size={18} /></Button>
            </div>
            <p className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 p-3 text-xs leading-5 text-amber-950">
              <strong>{pendingFirstSale.product.name}</strong> est disponible en interne. Ce prix est requis pour l’ajouter à la vente et restera privé tant que le stock n’est pas initialisé.
            </p>
            <div className="mt-4">
              <label className="text-xs font-bold text-gray-700">Prix de vente (FCFA)</label>
              <Input type="number" inputMode="numeric" min="1" value={firstSalePrice} onChange={(event) => setFirstSalePrice(event.target.value)} placeholder="Ex. 500" autoFocus className="mt-1 w-full rounded-xl bg-gray-100 px-3 py-3 text-base font-bold text-gray-900 outline-none" />
            </div>
            <Button
              disabled={!Number.isSafeInteger(Number(firstSalePrice)) || Number(firstSalePrice) < 1}
              onClick={() => {
                const result = onSetCatalogueDraftPrice(pendingFirstSale.product, Number(firstSalePrice))
                if (!result.product) { showToast?.(result.error ?? 'Le prix de vente est invalide.'); return }
                setCartProductQuantity(result.product, pendingFirstSale.qty)
                setPendingFirstSale(null)
              }}
              className="mt-4 w-full rounded-2xl bg-blue-600 py-3.5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
            >
              Ajouter au panier
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL 2: Produit hors catalogue ── */}
      {uncataloguedModalOpen && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
          onClick={() => setUncataloguedModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-blue-50 flex items-center justify-center text-blue-600">
                  <Plus size={18} />
                </div>
                <h3 className="font-bold text-gray-900 text-base">Produit hors catalogue</h3>
              </div>
              <Button onClick={() => setUncataloguedModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-xs font-bold text-gray-700">Nom du produit libre</label>
                <Input
                  type="text"
                  value={uncataloguedName}
                  onChange={(e) => setUncataloguedName(e.target.value)}
                  placeholder="Ex: Sac plastique extra, Canette 33cl..."
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                  autoFocus
                />
              </div>
              <div>
                <label className="text-xs font-bold text-gray-700">Prix de vente (FCFA)</label>
                <Input
                  type="number"
                  value={uncataloguedPrice}
                  onChange={(e) => setUncataloguedPrice(e.target.value)}
                  placeholder="Ex: 500"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                />
              </div>
            </div>

            <Button
              disabled={!uncataloguedName.trim() || !uncataloguedPrice}
              onClick={() => {
                const uncatProd: Product = {
                  id: `uncat-${Date.now()}`,
                  name: uncataloguedName.trim(),
                  price: Number(uncataloguedPrice),
                  stock: 99,
                  category: activeSector,
                  emoji: '📦',
                  isUncatalogued: true,
                }
                setCart((prev) => [...prev, { product: uncatProd, qty: 1 }])
                setUncataloguedName('')
                setUncataloguedPrice('')
                setUncataloguedModalOpen(false)
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-all disabled:opacity-40 shadow-md"
            >
              Ajouter au panier avec le badge "Nouveau"
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL 3: Initialisation du stock après une vente interne ── */}
      {postCheckoutStockPrompt && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
        >
          <div className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-2xl bg-amber-100 text-amber-700 flex items-center justify-center">
                <Package size={22} />
              </div>
              <div>
                <p className="text-[10px] font-bold text-amber-700 uppercase tracking-wider">Initialisation catalogue</p>
                <h3 className="font-bold text-gray-900 text-base">Initialiser le stock maintenant ?</h3>
              </div>
            </div>

            <p className="text-xs text-gray-600 leading-relaxed bg-gray-50 p-3 rounded-2xl border border-gray-100">
              Vous avez vendu <span className="font-bold text-gray-900">{postCheckoutStockPrompt.product.name}</span>. Le prix de vente de cette transaction est proposé ci-dessous. Un produit est publié au catalogue client seulement lorsque son prix et son stock sont définis.
            </p>

            <div className="space-y-3">
              {postCheckoutStockPrompt.source === 'uncatalogued' && <div>
                <label className="text-xs font-bold text-gray-700">Catégorie</label>
                <Input
                  type="text"
                  value={postStockCategory}
                  onChange={(e) => setPostStockCategory(e.target.value)}
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-sm font-semibold outline-none"
                />
              </div>}
              <div>
                <label className="text-xs font-bold text-gray-700">Prix de vente (FCFA)</label>
                <Input
                  type="number"
                  inputMode="numeric"
                  min="1"
                  value={postStockPrice}
                  onChange={(e) => setPostStockPrice(e.target.value)}
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-sm font-semibold outline-none"
                />
              </div>
              <div>
                <label className="text-xs font-bold text-gray-700">Stock disponible après cette vente</label>
                <Input
                  type="number"
                  inputMode="numeric"
                  min="0"
                  value={postStockQty}
                  onChange={(e) => setPostStockQty(e.target.value)}
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-sm font-semibold outline-none"
                />
              </div>
            </div>

            <div className="flex gap-2 pt-2">
              <Button
                onClick={dismissStockInitialisation}
                className="flex-1 py-3 rounded-2xl text-gray-600 font-bold text-xs bg-gray-100 hover:bg-gray-200 transition-colors"
              >
                Plus tard
              </Button>
              <Button
                onClick={() => {
                  const sellingPrice = Number(postStockPrice)
                  const stock = Number(postStockQty)
                  if (!Number.isSafeInteger(sellingPrice) || sellingPrice < 1 || !Number.isSafeInteger(stock) || stock < 0) {
                    showToast?.('Renseignez un prix de vente et un stock valides.')
                    return
                  }
                  if (postCheckoutStockPrompt.source === 'central') {
                    const error = onActivateCatalogueProduct({ ...postCheckoutStockPrompt.product, price: sellingPrice, stock })
                    if (error) { showToast?.(error); return }
                  } else {
                    const permProduct: Product = { ...postCheckoutStockPrompt.product, price: sellingPrice, category: postStockCategory || activeSector, stock, isUncatalogued: false }
                    setProducts((prev) => [...prev, permProduct])
                  }
                  dismissStockInitialisation()
                }}
                disabled={!Number.isSafeInteger(Number(postStockPrice)) || Number(postStockPrice) < 1 || postStockQty === '' || !Number.isSafeInteger(Number(postStockQty)) || Number(postStockQty) < 0}
                className="flex-1 py-3 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-transform shadow-md"
              >
                Enregistrer et publier
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* ── MODAL: SIMULATEUR SCANNER CODE-BARRES ── */}
      {barcodeScanOpen && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}
        >
          <div className="w-full bg-white rounded-3xl p-6 space-y-4 shadow-2xl text-center animate-in zoom-in-95 duration-200">
            <div className="relative w-20 h-20 mx-auto rounded-2xl bg-blue-50 border border-blue-100 flex items-center justify-center overflow-hidden">
              <QrCode size={36} color="#0050FF" />
              {barcodeStatus === 'scanning' && (
                <div className="absolute inset-x-0 h-1 bg-blue-600 animate-pulse top-1/2 shadow-md shadow-blue-500/50" />
              )}
            </div>

            {barcodeStatus === 'scanning' && (
              <div>
                <h3 className="font-bold text-gray-900 text-base">Lecture du code-barres…</h3>
                <p className="text-xs text-gray-400 mt-1">Scan du produit en cours</p>
                <div className="flex justify-center items-center gap-1 mt-3">
                  {[0, 1, 2].map((i) => (
                    <div
                      key={i}
                      className="w-2 h-2 rounded-full bg-blue-600 animate-bounce"
                      style={{ animationDelay: `${i * 150}ms` }}
                    />
                  ))}
                </div>
              </div>
            )}

            {barcodeStatus === 'found' && scannedProduct && (
              <div className="animate-in fade-in zoom-in-95 duration-150 space-y-1">
                <div className="inline-flex items-center justify-center w-8 h-8 rounded-full bg-green-100 text-green-600 mb-1">
                  <CheckCircle size={20} />
                </div>
                <h3 className="font-bold text-gray-900 text-base">{scannedProduct.name}</h3>
                <p className="text-xs text-green-600 font-bold">
                  +{scannedProduct.price.toLocaleString('fr-FR')} FCFA · Ajouté au panier !
                </p>
              </div>
            )}

            {barcodeStatus === 'not_found' && (
              <div className="animate-in fade-in duration-150 space-y-1">
                <div className="inline-flex items-center justify-center w-8 h-8 rounded-full bg-amber-100 text-amber-600 mb-1">
                  <AlertTriangle size={20} />
                </div>
                <h3 className="font-bold text-gray-900 text-base">Produit non trouvé en stock</h3>
                <p className="text-xs text-amber-700 font-semibold">
                  Ouverture de la saisie hors catalogue…
                </p>
              </div>
            )}

            <Button
              onClick={() => setBarcodeScanOpen(false)}
              className="w-full py-2.5 rounded-xl bg-gray-100 text-gray-600 font-bold text-xs hover:bg-gray-200 transition-colors mt-2"
            >
              Annuler
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL: REMISE % OU FCFA ── */}
      {discountModalOpen && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(2px)' }}
          onClick={() => setDiscountModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div>
                <h3 className="font-bold text-gray-900 text-base">Application d'une Remise</h3>
                <p className="text-xs text-blue-600 font-medium">Panier : {rawTotal.toLocaleString('fr-FR')} FCFA</p>
              </div>
              <Button onClick={() => setDiscountModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div className="grid grid-cols-4 gap-2">
              {[5, 10, 15, 20].map((pct) => (
                <Button
                  key={pct}
                  onClick={() => {
                    const discount = Math.round((rawTotal * pct) / 100)
                    setDiscountPercent(pct)
                    setAppliedDiscount(discount)
                  }}
                  className={`py-3 rounded-2xl font-bold text-xs transition-all ${discountPercent === pct ? 'bg-blue-600 text-white shadow-sm' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                >
                  {pct}%
                </Button>
              ))}
            </div>

            {discountPercent > 15 && (
              <div className="p-3 bg-amber-50 border border-amber-200 rounded-2xl flex items-center gap-2 text-xs text-amber-900 font-bold">
                <AlertTriangle size={16} color="#F79009" />
                <span>⚠️ Remise &gt; 15% — Approbation Supervision requise</span>
              </div>
            )}

            <div className="p-3 bg-blue-50/70 border border-blue-100 rounded-2xl flex justify-between items-center text-xs">
              <span className="font-bold text-gray-700">Montant de la remise :</span>
              <span className="font-bold text-blue-700 text-sm">-{appliedDiscount.toLocaleString('fr-FR')} FCFA</span>
            </div>

            <Button
              onClick={() => {
                setDiscountModalOpen(false)
                showToast?.(appliedDiscount > 0 ? `Remise de ${appliedDiscount.toLocaleString('fr-FR')} FCFA appliquée !` : "Aucune remise appliquée.")
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-transform shadow-md"
            >
              Appliquer cette remise
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL: CRÉER UN DEVIS / RÉSERVATION ── */}
      {createDevisModalOpen && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(2px)' }}
          onClick={() => setCreateDevisModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div>
                <h3 className="font-bold text-gray-900 text-base">Créer un Devis / Proforma</h3>
                <p className="text-xs text-purple-600 font-medium">Panier : {total.toLocaleString('fr-FR')} FCFA (Sans déduction stock)</p>
              </div>
              <Button onClick={() => setCreateDevisModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div>
              <label className="text-xs font-bold text-gray-700">Nom du client ou établissement</label>
              <Input
                type="text"
                value={devisClientName}
                onChange={(e) => setDevisClientName(e.target.value)}
                placeholder="Ex: Hôtel Sawa / M. Etoa"
                className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-sm font-bold text-gray-900 outline-none"
                autoFocus
              />
            </div>

            <div>
              <label className="text-xs font-bold text-gray-700">Téléphone (Optionnel)</label>
              <Input
                type="text"
                value={devisClientPhone}
                onChange={(e) => setDevisClientPhone(e.target.value)}
                placeholder="Ex: 699001122"
                className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-sm font-bold text-gray-900 outline-none"
              />
            </div>

            <Button
              disabled={!devisClientName.trim()}
              onClick={() => {
                const newDevis = {
                  id: `dev-${Date.now()}`,
                  code: `DEV-2026-00${devisList.length + 1}`,
                  clientName: devisClientName.trim(),
                  date: "Aujourd'hui",
                  items: [...cart],
                  total: total,
                }
                setDevisList((prev) => [newDevis, ...prev])
                setCart([])
                setCreateDevisModalOpen(false)
                setCartOpen(false)
                showToast?.(`Devis ${newDevis.code} généré pour ${newDevis.clientName} !`)
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-purple-600 active:scale-95 transition-transform shadow-md disabled:opacity-40"
            >
              Générer & Sauvegarder le Devis
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL: LISTE DES DEVIS / RÉSERVATIONS ── */}
      {devisListModalOpen && (
        <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200">
          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
            <Button
              onClick={() => setDevisListModalOpen(false)}
              className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
            >
              <ChevronLeft size={18} color="#1D2939" />
            </Button>
            <div className="text-center">
              <h2 className="text-base font-bold text-gray-900">Devis & Proformas en cours</h2>
              <p className="text-[11px] text-purple-600 font-medium">{devisList.length} devis enregistrés</p>
            </div>
            <Button
              onClick={() => setDevisListModalOpen(false)}
              className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
            >
              <X size={18} />
            </Button>
          </div>

          <div className="p-4 space-y-3 flex-1">
            {devisList.map((d) => (
              <div key={d.id} className="bg-white rounded-2xl p-4 border border-gray-100 space-y-3 shadow-xs">
                <div className="flex items-start justify-between">
                  <div>
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-50 text-purple-700">
                      {d.code}
                    </span>
                    <h3 className="text-sm font-bold text-gray-900 mt-1">{d.clientName}</h3>
                    <p className="text-xs text-gray-400">{d.date} · {d.items.reduce((s, i) => s + i.qty, 0)} articles</p>
                  </div>
                  <div className="text-right">
                    <p className="text-base font-bold text-purple-700">{d.total.toLocaleString('fr-FR')} FCFA</p>
                  </div>
                </div>

                <div className="bg-gray-50 rounded-xl p-2.5 space-y-1 text-xs text-gray-700">
                  {d.items.map((i) => (
                    <div key={i.product.id} className="flex justify-between">
                      <span>{i.product.name} × {i.qty}</span>
                      <span className="font-semibold">{(i.product.price * i.qty).toLocaleString('fr-FR')} F</span>
                    </div>
                  ))}
                </div>

                <Button
                  onClick={() => {
                    setCart([...d.items])
                    setDevisListModalOpen(false)
                    setCartOpen(true)
                    showToast?.(`Devis ${d.code} chargé dans le panier actif !`)
                  }}
                  className="w-full py-2.5 rounded-xl bg-purple-600 text-white font-bold text-xs hover:bg-purple-700 transition-colors flex items-center justify-center gap-1.5 shadow-xs"
                >
                  <ShoppingCart size={14} />
                  <span>Charger en Caisse & Encaisser</span>
                </Button>
              </div>
            ))}
          </div>
        </div>
      )}



      {/* ── MODAL: NÉGOCIATION DE PRIX UNITAIRE (VENTE ASSISTÉE) ── */}
      {itemNegotiationModalOpen && negotiatingItem && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(2px)' }}
          onClick={() => setItemNegotiationModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div>
                <h3 className="font-bold text-gray-900 text-base flex items-center gap-1.5">
                  🏷️ Négociation de Prix
                  <span className="text-[9px] font-bold px-2 py-0.5 rounded-full bg-purple-100 text-purple-700">Vente Assistée</span>
                </h3>
                <p className="text-xs text-gray-400 font-medium">{negotiatingItem.product.name}</p>
              </div>
              <Button onClick={() => setItemNegotiationModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            {/* Product Header Card */}
            <div className="p-3 bg-purple-50/70 border border-purple-100 rounded-2xl flex items-center justify-between">
              <div className="flex items-center gap-3">
                <span className="text-3xl">{negotiatingItem.product.emoji}</span>
                <div>
                  <p className="text-xs font-bold text-gray-900">{negotiatingItem.product.name}</p>
                  <p className="text-[10px] text-gray-500">Prix conseillé : <span className="font-bold text-gray-900">{negotiatingItem.product.price.toLocaleString('fr-FR')} FCFA</span></p>
                </div>
              </div>
              <span className="text-xs font-bold text-purple-700 bg-white px-2.5 py-1 rounded-xl shadow-2xs">
                {negotiatingItem.qty} unité{negotiatingItem.qty > 1 ? 's' : ''}
              </span>
            </div>

            {/* Price inputs */}
            <div className="space-y-3">
              <div>
                <label className="text-xs font-bold text-gray-700">Nouveau prix unitaire négocié (FCFA)</label>
                <Input
                  type="number"
                  value={negotiatedPriceInput}
                  onChange={(e) => setNegotiatedPriceInput(e.target.value)}
                  placeholder={String(negotiatingItem.product.price)}
                  className="w-full mt-1 bg-gray-100 rounded-2xl px-4 py-3 text-base font-bold text-purple-900 outline-none border border-purple-200 focus:border-purple-600 transition-all"
                  autoFocus
                />
              </div>

              {/* Thresholds & Margin Calculation */}
              {(() => {
                const negoPrice = Number(negotiatedPriceInput) || negotiatingItem.product.price
                const minAllowedPrice = Math.round(negotiatingItem.product.price * 0.75)
                const estimatedCost = Math.round(negotiatingItem.product.price * 0.55)
                const marginUnit = negoPrice - estimatedCost
                const totalMargin = marginUnit * negotiatingItem.qty
                const marginPct = Math.round((marginUnit / negoPrice) * 100)
                const isTooLow = negoPrice < minAllowedPrice

                return (
                  <div className="space-y-2">
                    <div className="grid grid-cols-2 gap-2 text-[11px]">
                      <div className="p-2.5 rounded-xl bg-gray-50 border border-gray-100">
                        <span className="text-gray-400 block font-medium">Prix Min. Autorisé</span>
                        <span className="font-bold text-gray-800">{minAllowedPrice.toLocaleString('fr-FR')} FCFA</span>
                      </div>
                      <div className="p-2.5 rounded-xl bg-gray-50 border border-gray-100">
                        <span className="text-gray-400 block font-medium">Marge % Brute</span>
                        <span className={`font-bold ${isTooLow ? 'text-red-600' : marginPct >= 20 ? 'text-emerald-600' : 'text-amber-600'}`}>
                          {marginPct}%
                        </span>
                      </div>
                    </div>

                    <div className={`p-3 rounded-2xl text-xs font-bold flex items-center justify-between ${isTooLow
                      ? 'bg-red-50 text-red-700 border border-red-200'
                      : marginPct >= 20
                        ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                        : 'bg-amber-50 text-amber-800 border border-amber-200'
                      }`}>
                      <span>{isTooLow ? '⛔ Vente à perte (Sous le seuil min) !' : marginPct >= 20 ? '✅ Marge commerciale optimale' : '⚠️ Marge faible'}</span>
                      <span>{totalMargin > 0 ? `+${totalMargin.toLocaleString('fr-FR')} FCFA` : `${totalMargin.toLocaleString('fr-FR')} FCFA`}</span>
                    </div>
                  </div>
                )
              })()}
            </div>

            {/* Action buttons */}
            <div className="flex gap-2 pt-2">
              <Button
                onClick={() => {
                  setCustomPrices((prev) => {
                    const copy = { ...prev }
                    delete copy[negotiatingItem.product.id]
                    return copy
                  })
                  setItemNegotiationModalOpen(false)
                  showToast?.(`Prix conseillé réinitialisé pour ${negotiatingItem.product.name}`)
                }}
                className="flex-1 py-3 rounded-2xl bg-gray-100 text-gray-700 text-xs font-bold hover:bg-gray-200 transition-colors"
              >
                Réinitialiser
              </Button>
              <Button
                disabled={Number(negotiatedPriceInput) < Math.round(negotiatingItem.product.price * 0.75)}
                onClick={() => {
                  const newP = Number(negotiatedPriceInput)
                  if (newP) {
                    setCustomPrices((prev) => ({ ...prev, [negotiatingItem.product.id]: newP }))
                    showToast?.(`Prix de ${negotiatingItem.product.name} ajusté à ${newP.toLocaleString('fr-FR')} FCFA !`)
                  }
                  setItemNegotiationModalOpen(false)
                }}
                className="flex-1 py-3 rounded-2xl bg-purple-600 text-white text-xs font-bold hover:bg-purple-700 transition-colors shadow-md disabled:opacity-40"
              >
                Valider Prix Négocié
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ─── Screen: Accueil ──────────────────────────────────────────────────────────

function AccueilScreen({
  shopName,
  syncTransport,
  shopCity,
  onOpenReporting,
  onOpenCashClosure,
  onOpenCreditLedger,
  onOpenClientPwa,
  onOpenLoyaltyPromotions,
  onOpenExpenses,
  expenses = [],
  creditAccounts = [],
  products = [],
}: {
  shopName?: string
  syncTransport: SyncTransport
  shopCity?: string
  onOpenReporting?: () => void
  onOpenCashClosure?: () => void
  onOpenCreditLedger?: () => void
  onOpenClientPwa?: () => void
  onOpenLoyaltyPromotions?: () => void
  onOpenExpenses?: () => void
  expenses?: Expense[]
  creditAccounts?: CreditAccount[]
  products?: Product[]
}) {
  const [alertsOpen, setAlertsOpen] = useState(true)
  const [timeframe, setTimeframe] = useState<'heures' | 'semaine' | 'mois'>('semaine')
  const [hoveredBar, setHoveredBar] = useState<{ label: string; amount: number; sales: number } | null>(null)

  const totalOutstandingDebt = creditAccounts.reduce((sum, acc) => sum + getAccountBalance(acc), 0)
  const todayDateStr = new Date().toLocaleDateString('fr-FR')
  const expensesToday = expenses
    .filter((e) => e.date === todayDateStr)
    .reduce((sum, e) => sum + e.amount, 0)

  const stockAlerts = products.filter((product) => product.alert)
  const kpis = [
    { label: 'Total articles', value: products.length, trend: 'Catalogue actif', icon: <Package size={18} />, tone: 'info' as const },
    { label: 'Stock faible', value: products.filter((product) => product.alert === 'low').length, trend: 'À réapprovisionner', icon: <AlertTriangle size={18} />, tone: 'warning' as const },
    { label: 'Rupture critique', value: products.filter((product) => product.alert === 'critical' || product.stock <= 0).length, trend: 'Action requise', icon: <TrendingDown size={18} />, tone: 'danger' as const },
  ]

  const recentSales = [
    { id: 'V-0428', items: 'Huile · Sucre · Sel', total: '2 350', time: 'il y a 8 min', mode: 'Espèces' },
    { id: 'V-0427', items: 'Riz · Lait concentré', total: '5 050', time: 'il y a 21 min', mode: 'Mobile Money' },
    { id: 'V-0426', items: 'Biscuits × 4', total: '1 800', time: 'il y a 35 min', mode: 'Espèces' },
    { id: 'V-0425', items: 'Eau min. × 6 · Café', total: '4 000', time: 'il y a 52 min', mode: 'Mixte' },
  ]

  // Test data for statistical charts
  const revenueByPeriod = {
    heures: [
      { label: '08h', h: 30, amount: 4500, sales: 3, isPeak: false },
      { label: '10h', h: 55, amount: 8200, sales: 5, isPeak: false },
      { label: '12h', h: 90, amount: 14500, sales: 7, isPeak: true },
      { label: '14h', h: 42, amount: 6800, sales: 3, isPeak: false },
      { label: '16h', h: 68, amount: 11200, sales: 5, isPeak: false },
      { label: '18h', h: 100, amount: 18500, sales: 9, isPeak: true },
      { label: '20h', h: 48, amount: 7600, sales: 4, isPeak: false },
    ],
    semaine: [
      { label: 'Lun', h: 52, amount: 52000, sales: 21, isPeak: false },
      { label: 'Mar', h: 65, amount: 65000, sales: 26, isPeak: false },
      { label: 'Mer', h: 44, amount: 44000, sales: 18, isPeak: false },
      { label: 'Jeu', h: 78, amount: 78000, sales: 31, isPeak: false },
      { label: 'Ven', h: 88, amount: 88500, sales: 38, isPeak: true },
      { label: 'Sam', h: 95, amount: 95000, sales: 42, isPeak: true },
      { label: 'Dim', h: 35, amount: 35000, sales: 14, isPeak: false },
    ],
    mois: [
      { label: 'Sem 1', h: 60, amount: 280000, sales: 112, isPeak: false },
      { label: 'Sem 2', h: 75, amount: 340000, sales: 135, isPeak: false },
      { label: 'Sem 3', h: 85, amount: 390000, sales: 154, isPeak: true },
      { label: 'Sem 4', h: 50, amount: 230000, sales: 98, isPeak: false },
    ],
  }

  const paymentBreakdown = [
    { mode: 'Espèces', pct: 48, amount: 22704, color: '#0050FF', bg: 'bg-blue-50', text: 'text-blue-700' },
    { mode: 'Mobile Money', pct: 32, amount: 15136, color: '#12B76A', bg: 'bg-emerald-50', text: 'text-emerald-700' },
    { mode: 'Carnet de Dette', pct: 15, amount: 7095, color: '#F79009', bg: 'bg-amber-50', text: 'text-amber-700' },
    { mode: 'Paiement Mixte', pct: 5, amount: 2365, color: '#7A5AF8', bg: 'bg-purple-50', text: 'text-purple-700' },
  ]

  const categoryBreakdown = [
    { name: 'Épicerie', emoji: '🛒', pct: 42, amount: 19866, itemsCount: 12, color: 'from-indigo-600 to-blue-600' },
    { name: 'Boissons', emoji: '🥤', pct: 28, amount: 13244, itemsCount: 8, color: 'from-emerald-500 to-teal-600' },
    { name: 'Hygiène', emoji: '🧼', pct: 18, amount: 8514, itemsCount: 4, color: 'from-purple-600 to-indigo-600' },
    { name: 'Conserves', emoji: '🥫', pct: 12, amount: 5676, itemsCount: 3, color: 'from-amber-500 to-orange-600' },
  ]

  const currentChartData = revenueByPeriod[timeframe]

  return (
    <div className="lk-home flex flex-col h-full overflow-y-auto">
      {/* Greeting Bar */}
      <div className="bg-white px-4 pt-3 pb-3 border-b border-gray-100 animate-cascade stagger-1">
        <div className="flex items-start justify-between gap-3">
          <p className="text-[11px] font-medium text-gray-400">Vendredi 25 juillet 2025</p>
          <SyncIndicator transport={syncTransport} />
        </div>
        <p className="text-xs text-gray-500 mt-2">{shopName || 'Boutique active'} · {shopCity || 'Ville non renseignée'}</p>
      </div>

      <div className="px-4 py-4 space-y-4">
        {/* Quick Action Grid (4 module shortcuts) */}
        <div className="grid grid-cols-2 gap-2 animate-cascade stagger-2">
          <Button
            onClick={onOpenExpenses}
            className="p-3 rounded-2xl bg-rose-50 border border-rose-100 flex items-center gap-2.5 active:scale-95 transition-transform text-left shadow-2xs font-sans cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-rose-600 text-white flex items-center justify-center flex-shrink-0 shadow-xs">
              <TrendingDown size={18} />
            </div>
            <div>
              <p className="text-xs font-bold text-gray-900 leading-tight">Dépenses & OPEX</p>
              <p className="text-[10px] text-rose-700 font-medium mt-0.5">{expensesToday > 0 ? `${expensesToday.toLocaleString('fr-FR')} F engagés` : 'Saisie & Caisse'}</p>
            </div>
          </Button>

          <Button
            onClick={onOpenReporting}
            className="p-3 rounded-2xl bg-blue-50 border border-blue-100 flex items-center gap-2.5 active:scale-95 transition-transform text-left shadow-2xs cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-blue-600 text-white flex items-center justify-center flex-shrink-0 shadow-xs">
              <PieChart size={18} />
            </div>
            <div>
              <p className="text-xs font-bold text-gray-900 leading-tight">Rapports & Marges</p>
              <p className="text-[10px] text-blue-700 font-medium mt-0.5">Analyse du CA & PDF</p>
            </div>
          </Button>

          <Button
            onClick={onOpenCashClosure}
            className="p-3 rounded-2xl bg-emerald-50 border border-emerald-100 flex items-center gap-2.5 active:scale-95 transition-transform text-left shadow-2xs cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-emerald-600 text-white flex items-center justify-center flex-shrink-0 shadow-xs">
              <Lock size={18} />
            </div>
            <div>
              <p className="text-xs font-bold text-gray-900 leading-tight">Clôture Caisse (Z)</p>
              <p className="text-[10px] text-emerald-700 font-medium mt-0.5">Comptage & Écarts</p>
            </div>
          </Button>

          <Button
            onClick={onOpenCreditLedger}
            className="p-3 rounded-2xl bg-amber-50 border border-amber-100 flex items-center gap-2.5 active:scale-95 transition-transform text-left shadow-2xs cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-amber-600 text-white flex items-center justify-center flex-shrink-0 shadow-xs">
              <UserPlus size={18} />
            </div>
            <div>
              <p className="text-xs font-bold text-gray-900 leading-tight">Carnet de Dette</p>
              <p className="text-[10px] text-amber-700 font-medium mt-0.5">{totalOutstandingDebt.toLocaleString('fr-FR')} F dûs</p>
            </div>
          </Button>

          <Button
            onClick={onOpenClientPwa}
            className="p-3 rounded-2xl bg-purple-50 border border-purple-100 flex items-center gap-2.5 active:scale-95 transition-transform text-left shadow-2xs cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-purple-600 text-white flex items-center justify-center flex-shrink-0 shadow-xs">
              <QrCode size={18} />
            </div>
            <div>
              <p className="text-xs font-bold text-gray-900 leading-tight">Client PWA / USSD</p>
              <p className="text-[10px] text-purple-700 font-medium mt-0.5">Tester Mobile Money</p>
            </div>
          </Button>

          <Button
            onClick={onOpenLoyaltyPromotions}
            className="p-3 rounded-2xl bg-indigo-50 border border-indigo-100 flex items-center gap-2.5 active:scale-95 transition-transform text-left shadow-2xs font-sans cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-indigo-600 text-white flex items-center justify-center flex-shrink-0 shadow-xs">
              <Gift size={18} />
            </div>
            <div>
              <p className="text-xs font-bold text-gray-900 leading-tight">Fidélité & Coupons</p>
              <p className="text-[10px] text-indigo-700 font-medium mt-0.5">Points & Offres</p>
            </div>
          </Button>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-3 gap-3 animate-cascade stagger-3">
          {kpis.map((kpi) => <LynkstorMetricCard key={kpi.label} label={kpi.label} value={kpi.value} trend={kpi.trend} icon={kpi.icon} tone={kpi.tone} />)}
        </div>

        {/* ── DIAGRAMME 1 : Courbe d'Évolution du CA (Smooth Area Line Chart) ── */}
        <div className="bg-white rounded-2xl p-4 border border-gray-100 animate-cascade stagger-4 space-y-3 shadow-2xs">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-gray-400 font-medium">Statistiques de vente</p>
              <p className="text-base font-bold text-gray-900">Évolution du Chiffre d'Affaires</p>
            </div>
            {/* Filter Pills */}
            <div className="flex bg-slate-100 p-0.5 rounded-xl text-[11px] font-bold">
              {[
                { key: 'heures', label: 'Heures' },
                { key: 'semaine', label: 'Semaine' },
                { key: 'mois', label: 'Mois' },
              ].map(({ key, label }) => (
                <Button
                  key={key}
                  onClick={() => {
                    setTimeframe(key as typeof timeframe)
                    setHoveredBar(null)
                  }}
                  className={`px-2.5 py-1 rounded-lg transition-all ${timeframe === key ? 'bg-white text-indigo-600 shadow-2xs font-extrabold' : 'text-slate-500'
                    }`}
                >
                  {label}
                </Button>
              ))}
            </div>
          </div>

          {/* Interactive Tooltip readout */}
          <div className="min-h-[28px] flex items-center justify-between bg-indigo-50/60 px-3 py-1.5 rounded-xl border border-indigo-100 text-xs">
            {hoveredBar ? (
              <>
                <span className="font-bold text-indigo-900">{hoveredBar.label} : <span className="text-indigo-600">{hoveredBar.amount.toLocaleString('fr-FR')} FCFA</span></span>
                <span className="text-[11px] font-semibold text-indigo-700">{hoveredBar.sales} vente{hoveredBar.sales > 1 ? 's' : ''}</span>
              </>
            ) : (
              <span className="text-slate-500 italic text-[11px]">💡 Survolez ou touchez un point de la courbe pour voir le détail</span>
            )}
          </div>

          {/* SVG Smooth Curve Graph */}
          {(() => {
            const chartWidth = 300
            const chartHeight = 85
            const points = currentChartData.map((item, i) => {
              const x = (i / Math.max(1, currentChartData.length - 1)) * (chartWidth - 30) + 15
              const y = chartHeight - 12 - (item.h / 100) * 58
              return { x, y, item }
            })

            const strokePath = points.reduce((acc, pt, i, arr) => {
              if (i === 0) return `M ${pt.x},${pt.y}`
              const prev = arr[i - 1]
              const cx = (prev.x + pt.x) / 2
              return `${acc} C ${cx},${prev.y} ${cx},${pt.y} ${pt.x},${pt.y}`
            }, '')

            const fillAreaPath = `${strokePath} L ${points[points.length - 1].x},${chartHeight - 4} L ${points[0].x},${chartHeight - 4} Z`

            return (
              <div className="space-y-1">
                <div className="relative w-full h-32 pt-1">
                  <svg className="w-full h-full overflow-visible" viewBox={`0 0 ${chartWidth} ${chartHeight}`} preserveAspectRatio="none">
                    <defs>
                      <linearGradient id="areaGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#4F46E5" stopOpacity="0.35" />
                        <stop offset="90%" stopColor="#7C3AED" stopOpacity="0.0" />
                      </linearGradient>
                      <linearGradient id="lineGradient" x1="0" y1="0" x2="1" y2="0">
                        <stop offset="0%" stopColor="#4F46E5" />
                        <stop offset="50%" stopColor="#7C3AED" />
                        <stop offset="100%" stopColor="#06B6D4" />
                      </linearGradient>
                    </defs>

                    {/* Horizontal grid lines */}
                    {[20, 45, 70].map((gridY) => (
                      <line key={gridY} x1="10" y1={gridY} x2="290" y2={gridY} stroke="#F1F5F9" strokeWidth="1" strokeDasharray="3 3" />
                    ))}

                    {/* Gradient Area under curve */}
                    <path d={fillAreaPath} fill="url(#areaGradient)" />

                    {/* Main Curve Line */}
                    <path d={strokePath} fill="none" stroke="url(#lineGradient)" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />

                    {/* Data Points */}
                    {points.map(({ x, y, item }) => {
                      const isSelected = hoveredBar?.label === item.label
                      return (
                        <g
                          key={item.label}
                          className="cursor-pointer group"
                          onMouseEnter={() => setHoveredBar({ label: item.label, amount: item.amount, sales: item.sales })}
                          onClick={() => setHoveredBar({ label: item.label, amount: item.amount, sales: item.sales })}
                        >
                          {/* Invisible hit area */}
                          <circle cx={x} cy={y} r="12" fill="transparent" />

                          {/* Outer halo ring */}
                          {(isSelected || item.isPeak) && (
                            <circle
                              cx={x}
                              cy={y}
                              r={isSelected ? 7.5 : 5.5}
                              fill="none"
                              stroke={isSelected ? '#4F46E5' : '#7C3AED'}
                              strokeWidth="2"
                              opacity={isSelected ? '0.9' : '0.5'}
                              className={isSelected ? 'animate-ping' : ''}
                            />
                          )}

                          {/* Center point circle */}
                          <circle
                            cx={x}
                            cy={y}
                            r={isSelected ? 4.5 : item.isPeak ? 3.5 : 2.8}
                            fill={isSelected ? '#4F46E5' : '#FFFFFF'}
                            stroke={isSelected ? '#FFFFFF' : '#4F46E5'}
                            strokeWidth="2"
                            className="transition-all duration-200"
                          />
                        </g>
                      )
                    })}
                  </svg>
                </div>

                {/* X-Axis Labels */}
                <div className="flex justify-between px-2 pt-1 border-t border-slate-100">
                  {currentChartData.map((item) => {
                    const isSelected = hoveredBar?.label === item.label
                    return (
                      <Button
                        key={item.label}
                        onClick={() => setHoveredBar({ label: item.label, amount: item.amount, sales: item.sales })}
                        className={`text-[10px] font-bold transition-all ${isSelected ? 'text-indigo-600 font-extrabold scale-110' : 'text-slate-400 hover:text-slate-600'
                          }`}
                      >
                        {item.label}
                      </Button>
                    )
                  })}
                </div>
              </div>
            )
          })()}
        </div>

        {/* ── DIAGRAMME 2 : Ring Donut Modes de Paiement ── */}
        <div className="bg-white rounded-2xl p-4 border border-gray-100 animate-cascade stagger-5 space-y-3 shadow-2xs">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-gray-400 font-medium">Répartition Caisse</p>
              <p className="text-base font-bold text-gray-900">Modes de Paiement du Jour</p>
            </div>
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700">47 300 FCFA</span>
          </div>

          <div className="grid grid-cols-2 gap-3 items-center pt-1">
            {/* Donut Visual via SVG */}
            <div className="relative flex items-center justify-center py-1">
              <svg className="w-28 h-28 transform -rotate-90" viewBox="0 0 36 36">
                {/* Background Ring */}
                <path
                  className="text-slate-100"
                  strokeWidth="4"
                  stroke="currentColor"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                />
                {/* Espèces - 48% */}
                <path
                  strokeWidth="4.5"
                  strokeDasharray="48, 100"
                  stroke="#0050FF"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  strokeLinecap="round"
                />
                {/* Mobile Money - 32% */}
                <path
                  strokeWidth="4.5"
                  strokeDasharray="32, 100"
                  strokeDashoffset="-48"
                  stroke="#12B76A"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  strokeLinecap="round"
                />
                {/* Carnet de Dette - 15% */}
                <path
                  strokeWidth="4.5"
                  strokeDasharray="15, 100"
                  strokeDashoffset="-80"
                  stroke="#F79009"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  strokeLinecap="round"
                />
              </svg>
              <div className="absolute flex flex-col items-center justify-center text-center">
                <span className="text-xs font-extrabold text-slate-900">48%</span>
                <span className="text-[9px] font-medium text-slate-400">Cash</span>
              </div>
            </div>

            {/* Legend list */}
            <div className="space-y-1.5 text-xs">
              {paymentBreakdown.map((pm) => (
                <div key={pm.mode} className="flex items-center justify-between p-1.5 rounded-xl hover:bg-slate-50 transition-colors">
                  <div className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: pm.color }} />
                    <span className="font-semibold text-slate-800 text-[11px]">{pm.mode}</span>
                  </div>
                  <div className="text-right">
                    <span className="font-bold text-slate-900 text-[11px] block">{pm.pct}%</span>
                    <span className="text-[9px] text-slate-400">{pm.amount.toLocaleString('fr-FR')} F</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* ── DIAGRAMME 3 : Contribution par Catégorie Produit ── */}
        <div className="bg-white rounded-2xl p-4 border border-gray-100 animate-cascade stagger-6 space-y-3 shadow-2xs">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-gray-400 font-medium">Analyse Catalogue</p>
              <p className="text-base font-bold text-gray-900">Ventes par Catégorie</p>
            </div>
            <span className="text-xs font-bold text-indigo-600 bg-indigo-50 px-2.5 py-1 rounded-full">Top : Épicerie</span>
          </div>

          <div className="space-y-2.5">
            {categoryBreakdown.map((cat) => (
              <div key={cat.name} className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <div className="flex items-center gap-1.5">
                    <span className="text-sm">{cat.emoji}</span>
                    <span className="font-bold text-slate-800">{cat.name}</span>
                    <span className="text-[10px] text-slate-400">({cat.itemsCount} art.)</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-slate-900">{cat.amount.toLocaleString('fr-FR')} FCFA</span>
                    <span className="text-[10px] font-extrabold text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded-md">{cat.pct}%</span>
                  </div>
                </div>
                {/* Horizontal Progress Bar */}
                <div className="w-full h-2 bg-slate-100 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full bg-gradient-to-r ${cat.color} transition-all duration-500`}
                    style={{ width: `${cat.pct}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* ── DIAGRAMME 4 : Widget IA Rentabilité & Heures de Pointe ── */}
        <div className="bg-gradient-to-r from-slate-900 via-indigo-950 to-purple-950 rounded-2xl p-4 text-white shadow-md animate-cascade stagger-7 space-y-3 border border-indigo-900/50">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-xl bg-purple-600/50 border border-purple-400/30 flex items-center justify-center">
                <Sparkles size={16} className="text-purple-300" />
              </div>
              <div>
                <p className="text-[10px] font-bold uppercase tracking-wider text-purple-300">Analyse IA décisionnelle</p>
                <h3 className="text-sm font-extrabold text-white">Rentabilité & Heures de Pointe</h3>
              </div>
            </div>
            <span className="text-[10px] font-bold px-2.5 py-1 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">Marge : 31.8%</span>
          </div>

          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="p-2.5 rounded-xl bg-white/10 border border-white/10 space-y-1">
              <p className="text-[10px] text-slate-300 font-medium">Bénéfice estimé jour</p>
              <p className="text-base font-extrabold text-emerald-400">+15 040 FCFA</p>
              <p className="text-[9px] text-slate-400">Sur 47 300 F de CA</p>
            </div>
            <div className="p-2.5 rounded-xl bg-white/10 border border-white/10 space-y-1">
              <p className="text-[10px] text-slate-300 font-medium">Pic d'affluence caisse</p>
              <p className="text-sm font-extrabold text-indigo-300">18h00 – 19h30</p>
              <p className="text-[9px] text-purple-200 font-medium">⚡ 9 ventes / heure</p>
            </div>
          </div>
        </div>

        {/* Alertes */}
        <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden shadow-2xs">
          <Button
            className="w-full flex items-center justify-between px-4 py-3 border-b border-gray-100"
            onClick={() => setAlertsOpen(!alertsOpen)}
          >
            <div className="flex items-center gap-2">
              <div className="w-6 h-6 rounded-lg flex items-center justify-center bg-amber-50">
                <AlertTriangle size={13} color="#F79009" />
              </div>
              <span className="text-sm font-semibold text-gray-800">Alertes de stock</span>
              <LynkstorStatusBadge tone={stockAlerts.some((product) => product.alert === 'critical') ? 'danger' : 'warning'}>{stockAlerts.length}</LynkstorStatusBadge>
            </div>
            {alertsOpen ? <ChevronUp size={16} color="#98A2B3" /> : <ChevronDown size={16} color="#98A2B3" />}
          </Button>
          {alertsOpen && (
            <div className="divide-y divide-gray-50">
              {stockAlerts.length === 0 ? <p className="px-4 py-3 text-xs text-gray-500">Aucune alerte de stock active.</p> : stockAlerts.map((alert) => (
                <div key={alert.id} className="flex items-start gap-3 px-4 py-3">
                  <div
                    className="w-2 h-2 rounded-full mt-1.5 flex-shrink-0"
                    style={{ backgroundColor: alert.alert === 'critical' ? '#FF3B4D' : '#FF9800' }}
                  />
                  <div className="flex-1">
                    <p className="text-sm font-semibold text-gray-800">{alert.name}</p>
                    <p className="text-xs text-gray-400 mt-0.5">{alert.alert === 'critical' ? `Stock critique : ${alert.stock} unité${alert.stock > 1 ? 's' : ''} restante${alert.stock > 1 ? 's' : ''}` : `Stock faible : ${alert.stock} unité${alert.stock > 1 ? 's' : ''} — prévoir le réassort`}</p>
                  </div>
                  <ChevronRight size={15} color="#D0D5DD" />
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Ventes récentes */}
        <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden shadow-2xs">
          <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
            <span className="text-sm font-semibold text-gray-800">Ventes récentes</span>
            <Button className="text-xs font-medium" style={{ color: '#0050FF' }}>Voir tout</Button>
          </div>
          <div className="divide-y divide-gray-50">
            {recentSales.map((sale) => (
              <div key={sale.id} className="flex items-center gap-3 px-4 py-3">
                <div className="w-9 h-9 rounded-xl flex items-center justify-center bg-blue-50 flex-shrink-0">
                  <ShoppingBag size={16} color="#0050FF" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-xs font-bold text-gray-600">{sale.id}</p>
                    <span className="text-[10px] text-gray-300">·</span>
                    <p className="text-[10px] text-gray-400">{sale.mode}</p>
                  </div>
                  <p className="text-sm font-medium text-gray-800 truncate">{sale.items}</p>
                  <p className="text-[10px] text-gray-400">{sale.time}</p>
                </div>
                <p className="text-sm font-bold text-gray-900 whitespace-nowrap">{sale.total} <span className="text-xs font-normal text-gray-400">FCFA</span></p>
              </div>
            ))}
          </div>
        </div>

        <div className="h-2" />
      </div>
    </div>
  )
}

// ─── Screen: Stock ────────────────────────────────────────────────────────────

interface StockScreenProps {
  products: Product[]
  setProducts: React.Dispatch<React.SetStateAction<Product[]>>
  stockMode: 'express' | 'assiste'
  setStockMode: React.Dispatch<React.SetStateAction<'express' | 'assiste'>>
  activeSector: string
  showToast?: (msg: string) => void
  stagedStockChanges: Record<string, number>
  setStagedStockChanges: React.Dispatch<React.SetStateAction<Record<string, number>>>
  setPendingMovementReasonSource: React.Dispatch<React.SetStateAction<'express' | 'assiste'>>
  setMovementReasonModalOpen: React.Dispatch<React.SetStateAction<boolean>>
  initialDetailStock: number
  setInitialDetailStock: React.Dispatch<React.SetStateAction<number>>
  selectedProductForDetail: Product | null
  setSelectedProductForDetail: React.Dispatch<React.SetStateAction<Product | null>>
  onCatalogueProductsSelected: (items: CatalogueItem[], reviewAcknowledged: boolean) => void
  onActivateCatalogueProduct: (product: Product) => string | null
  catalogueDisplay: 'grid' | 'list'
  showCatalogueImages: boolean
}

function StockScreen({
  products,
  setProducts,
  stockMode,
  setStockMode,
  activeSector,
  showToast,
  stagedStockChanges,
  setStagedStockChanges,
  setPendingMovementReasonSource,
  setMovementReasonModalOpen,
  initialDetailStock,
  setInitialDetailStock,
  selectedProductForDetail,
  setSelectedProductForDetail,
  onCatalogueProductsSelected,
  onActivateCatalogueProduct,
  catalogueDisplay,
  showCatalogueImages,
}: StockScreenProps) {
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('Tous')

  // Modals state
  const [invoiceScanOpen, setInvoiceScanOpen] = useState(false)
  const [invoiceStep, setInvoiceStep] = useState<'scanning' | 'lines'>('scanning')
  const [invoiceLines, setInvoiceLines] = useState<{ id: string; name: string; qty: number; price: number }[]>([
    { id: '1', name: 'Huile Végétale 1L', qty: 24, price: 1350 },
    { id: '2', name: 'Riz Basmati 5kg', qty: 10, price: 3800 },
    { id: '3', name: 'Sucre 1kg', qty: 20, price: 550 },
  ])

  const [newProductModalOpen, setNewProductModalOpen] = useState(false)
  const [newProdName, setNewProdName] = useState('')
  const [newProdCat, setNewProdCat] = useState(activeSector || 'Épicerie')
  const [newProdPrice, setNewProdPrice] = useState('')
  const [newProdStock, setNewProdStock] = useState('')
  const [newProdPackaging, setNewProdPackaging] = useState<'unite' | 'carton' | 'paquet'>('unite')
  const [newProdUnitsPerPack, setNewProdUnitsPerPack] = useState('12')
  const [catalogueOpen, setCatalogueOpen] = useState(false)

  // Typée Stock Movement state
  const [movementModalOpen, setMovementModalOpen] = useState(false)
  const [movementProduct, setMovementProduct] = useState<Product | null>(null)
  const [movementType, setMovementType] = useState<'entree' | 'sortie' | 'retour_client' | 'retour_fournisseur' | 'casse' | 'consommation' | 'ajustement'>('entree')
  const [movementQty, setMovementQty] = useState('10')
  const [movementComment, setMovementComment] = useState('')
  const [productMovements, setProductMovements] = useState<Record<string, { id: string; type: string; label: string; qty: string; date: string; comment: string }[]>>({})

  // Commercial Pricing Policy per Product state
  const [productPolicies, setProductPolicies] = useState<Record<string, 'fixed' | 'negotiable' | 'free' | 'on_order'>>({
    'p-1': 'fixed',
    'p-2': 'negotiable',
    'p-3': 'fixed',
  })

  // Package Calculator state
  const [pkgCalcCartons, setPkgCalcCartons] = useState('')

  const sectorCategories = SECTORS.find((s) => s.name === activeSector)?.categories || [
    'Épicerie',
    'Hygiène',
    'Boissons',
    'Conserves',
    'Biscuiterie',
  ]
  const categories = ['Tous', ...sectorCategories]

  const filtered = products.filter((p) => {
    const matchSearch = p.name.toLowerCase().includes(search.toLowerCase())
    const matchCat = category === 'Tous' || p.category === category
    return matchSearch && matchCat
  })

  const handleProductImageSelection = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    const supportedTypes = ['image/jpeg', 'image/png', 'image/webp']
    if (!supportedTypes.includes(file.type)) {
      showToast?.('Choisissez une image JPEG, PNG ou WebP.')
      return
    }
    if (file.size > 2 * 1024 * 1024) {
      showToast?.('L’image doit peser 2 Mo ou moins.')
      return
    }
    const reader = new FileReader()
    reader.onload = () => {
      if (typeof reader.result !== 'string') return
      setSelectedProductForDetail((product) => product ? { ...product, imageUrl: reader.result } : null)
      showToast?.('Image ajoutée. Enregistrez la fiche pour la retrouver dans le catalogue.')
    }
    reader.onerror = () => showToast?.('Impossible de lire cette image. Réessayez avec un autre fichier.')
    reader.readAsDataURL(file)
  }

  const alerts = products.filter((p) => p.alert)
  const totalValuation = products.reduce((s, p) => s + p.price * p.stock, 0)
  const draftCatalogueProducts = products.filter((p) => p.catalogueStatus === 'draft')



  // Start invoice scan simulation
  const handleOpenInvoiceScan = () => {
    setInvoiceScanOpen(true)
    setInvoiceStep('scanning')
    setTimeout(() => {
      setInvoiceStep('lines')
    }, 1500)
  }

  return (
    <div className="lk-stock-screen flex flex-col h-full relative">
      {/* Recherche et filtres du catalogue. Le contexte et le mode sont dans l'en-tête d'application. */}
      <div className="lk-stock-top bg-white px-4 pt-4 pb-3 border-b border-gray-100 space-y-2.5">
        {/* Recherche et actions de catalogue regroupées */}
        <div className="flex gap-2">
          <div className="lk-stock-search flex min-w-0 flex-1 items-center gap-2 bg-gray-100 rounded-xl px-3 py-2.5 justify-center">
            <Search size={16} color="#98A2B3" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Rechercher un produit..."
              className="flex-1 min-w-0 bg-transparent text-sm text-gray-700 placeholder-gray-400 outline-none"
            />
          </div>
          <Button
            onClick={handleOpenInvoiceScan}
            className="lk-stock-new-product rounded-xl bg-blue-600 flex items-center justify-center gap-1.5 text-white transition-all active:scale-95 shadow-sm"
            title="Réception par photo de facture (OCR)"
          >
            <Camera size={20} />
          </Button>
          <Button
            onClick={() => setCatalogueOpen(true)}
            className="lk-stock-new-product rounded-xl bg-blue-600 flex items-center justify-center gap-1.5 text-white transition-all active:scale-95 "
            title="Rechercher dans le catalogue métier"
          >
            <BookOpen size={19} />
          </Button>
          <Button
            onClick={() => setNewProductModalOpen(true)}
            className="lk-stock-new-product rounded-xl bg-blue-600 flex items-center justify-center gap-1.5 text-white transition-all active:scale-95 "
            title="Nouveau produit manuel"
          >
            <Plus size={20} />
          </Button>
        </div>

        {/* Category chips */}
        <div className="flex gap-2 overflow-x-auto pb-1 scrollbar-hide">
          {categories.map((cat) => (
            <Button
              key={cat}
              onClick={() => setCategory(cat)}
              className={`lk-stock-category flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-medium transition-all ${category === cat ? 'text-white' : 'bg-gray-100 text-gray-500'
                }`}
              style={category === cat ? { backgroundColor: '#FF9800' } : {}}
            >
              {cat}
            </Button>
          ))}
        </div>

        <div className="flex items-center flex items-center justify-between flex-shrink-0">
          <p className="text-[11px] font-medium text-gray-400">{filtered.length} résultat{filtered.length > 1 ? 's' : '...'}</p>
          <div className="lk-stock-display-switch flex items-rigth" role="tablist" aria-label="Affichage du stock">
              <Button role="tab" aria-label="Vue catalogue" aria-selected={stockMode === 'express'} onClick={() => setStockMode('express')} className={stockMode === 'express' ? 'is-active' : ''}><Package size={16} /> </Button>
              <Button role="tab" aria-label="Analyse et alertes" aria-selected={stockMode === 'assiste'} onClick={() => setStockMode('assiste')} className={stockMode === 'assiste' ? 'is-active' : ''}><BarChart3 size={16} /> </Button>
            </div>
        </div>
      </div>

      <div className="lk-stock-list flex-1 overflow-y-auto px-4 py-3 space-y-3">
        {draftCatalogueProducts.length > 0 && (
          <div className="rounded-2xl border border-amber-200 bg-amber-50 p-3.5 text-amber-950">
            <p className="text-sm font-extrabold">{draftCatalogueProducts.length} produit{draftCatalogueProducts.length > 1 ? 's' : ''} à finaliser</p>
            <p className="mt-1 text-xs leading-5">Ces fiches sont vendables au comptoir. Définissez leur prix et leur stock pour les publier au catalogue client.</p>
            <Button onClick={() => { setSelectedProductForDetail(draftCatalogueProducts[0]); setInitialDetailStock(draftCatalogueProducts[0].stock) }} className="mt-3 min-h-11 rounded-xl bg-amber-900 px-3 text-xs font-bold text-white">Compléter le premier produit</Button>
          </div>
        )}
        <div className="lk-stock-metrics grid grid-cols-3 gap-2" aria-label="Résumé des niveaux de stock">
          <div className="lk-stock-metric lk-stock-metric-danger rounded-2xl border border-red-100 bg-red-50 px-3 py-2">
            <p className="text-[10px] font-bold uppercase tracking-wide text-red-600">Critique</p>
            <p className="mt-0.5 text-lg font-bold text-red-700">{products.filter((p) => p.alert === 'critical').length}</p>
          </div>
          <div className="lk-stock-metric lk-stock-metric-warning rounded-2xl border border-amber-100 bg-amber-50 px-3 py-2">
            <p className="text-[10px] font-bold uppercase tracking-wide text-amber-700">Bas</p>
            <p className="mt-0.5 text-lg font-bold text-amber-700">{products.filter((p) => p.alert === 'low').length}</p>
          </div>
          <div className="lk-stock-metric lk-stock-metric-success rounded-2xl border border-emerald-100 bg-emerald-50 px-3 py-2">
            <p className="text-[10px] font-bold uppercase tracking-wide text-emerald-700">Valeur</p>
            <p className="mt-0.5 text-sm font-bold text-emerald-700">{totalValuation.toLocaleString('fr-FR')} F</p>
          </div>
        </div>

        {/* Stock Assisté Banner: Valorisation globale & Assistant IA Vivant */}
        {stockMode === 'assiste' && (
          <div className="space-y-3">
            <div className="p-3.5 bg-gradient-to-r from-blue-900 to-indigo-900 text-white rounded-2xl shadow-md flex items-center justify-between">
              <div>
                <p className="text-[10px] font-bold uppercase tracking-wider text-blue-200">Valeur totale du stock</p>
                <p className="text-base font-bold text-white mt-0.5">{totalValuation.toLocaleString('fr-FR')} FCFA</p>
              </div>
              <Button
                onClick={() => {
                  setMovementProduct(products[0] || null)
                  setMovementModalOpen(true)
                }}
                className="px-3 py-1.5 rounded-xl bg-white/20 hover:bg-white/30 text-white text-xs font-bold transition-all flex items-center gap-1.5 cursor-pointer shadow-2xs"
              >
                <TrendingUp size={14} />
                <span>+ Mouvement Typé</span>
              </Button>
            </div>

            {/* Assistant IA Stock Vivant Prédictif */}
            <div className="p-3.5 bg-gradient-to-r from-slate-900 via-indigo-950 to-purple-950 text-white rounded-2xl shadow-md space-y-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-7 h-7 rounded-xl bg-purple-600/60 flex items-center justify-center text-white">
                    <Bot size={16} />
                  </div>
                  <div>
                    <p className="text-xs font-bold text-white flex items-center gap-1.5">
                      Assistant IA Stock Vivant
                      <span className="text-[9px] bg-purple-500/30 text-purple-300 border border-purple-400/40 px-1.5 py-0.2 rounded-full font-bold">Prédictif</span>
                    </p>
                    <p className="text-[10px] text-slate-300">Analyse de rotation & anticipation de rupture</p>
                  </div>
                </div>
                <Button
                  onClick={() => {
                    const p = products.find(p => p.alert === 'critical') || products[0]
                    if (p) {
                      setMovementProduct(p)
                      setMovementType('entree')
                      setMovementQty('20')
                      setMovementComment('Suggestion de réassort à vérifier')
                      setMovementModalOpen(true)
                      showToast?.(`Suggestion préparée pour ${p.name} : vérifiez-la avant validation.`)
                    }
                  }}
                  className="px-2.5 py-1 rounded-xl bg-purple-600 hover:bg-purple-700 text-white text-[10px] font-bold shadow-xs active:scale-95 transition-transform"
                >
                  Préparer le réassort
                </Button>
              </div>

              <div className="bg-white/10 p-2.5 rounded-xl border border-white/10 text-[11px] text-slate-200 leading-relaxed">
                💡 <span className="font-bold text-amber-300">Prédiction Rupture :</span> <span className="font-semibold text-white">Sucre 1kg</span> sera en rupture dans <span className="font-bold text-amber-300">3 jours</span> au rythme actuel (7 u./jour). Fournisseur recommandé : <span className="font-bold text-blue-300">Grossiste Socapalm</span> (Prix : 520 F/u.).
              </div>
            </div>
          </div>
        )}

        {/* Alerts summary */}
        {alerts.length > 0 && search === '' && category === 'Tous' && (
          <div
            className="flex items-center gap-3 px-4 py-3 rounded-2xl"
            style={{ backgroundColor: '#FFF9EB' }}
          >
            <AlertTriangle size={18} color="#F79009" />
            <p className="text-sm text-amber-700 font-medium">
              {alerts.length} produit{alerts.length > 1 ? 's' : ''} nécessitent votre attention
            </p>
            <ChevronRight size={16} color="#F79009" className="ml-auto" />
          </div>
        )}

        {/* Product list */}
        <div className={catalogueDisplay === 'grid' ? 'grid grid-cols-2 gap-2' : 'space-y-3'} aria-label={`Catalogue en ${catalogueDisplay === 'grid' ? 'grille' : 'liste'}`}>
        {filtered.map((product, idx) => {
          const staggerClass = `stagger-${Math.min((idx % 8) + 1, 10)}`
          return (
            <div
              key={product.id}
              onClick={() => {
                setSelectedProductForDetail(product)
                setInitialDetailStock(product.stock)
              }}
              className={`lk-stock-card bg-white rounded-2xl border flex cursor-pointer hover:shadow-sm transition-all active:scale-[0.98] animate-cascade ${catalogueDisplay === 'grid' ? 'p-3 flex-col items-stretch gap-2' : 'p-3.5 items-center gap-3'} ${staggerClass} ${product.alert === 'critical'
                ? 'border-red-100'
                : product.alert === 'low'
                  ? 'border-amber-100'
                  : 'border-gray-100'
                }`}
            >
              {showCatalogueImages && <div className={`flex shrink-0 items-center justify-center rounded-xl border border-slate-100 bg-slate-50 ${catalogueDisplay === 'grid' ? 'h-24 w-full p-2' : 'h-16 w-16 p-1.5'}`}><ProductThumbnail product={product} className="h-full w-full" /></div>}
              <div className="flex-1 min-w-0">
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-gray-900 leading-tight break-words">{product.name}</p>
                  <p className="mt-0.5 truncate text-[10px] font-semibold text-blue-600" title={productReference(product)}>{productReference(product)}</p>
                </div>
                  <div className="mt-0.5 flex items-center gap-1.5 text-xs text-gray-400">
                    <ProductStockBadge product={product} />
                    <span>{product.category} {product.packaging && product.packaging !== 'unite' ? `· ${product.packaging === 'carton' ? 'Carton' : 'Paquet'} (${product.unitsPerPack || 12} u.)` : ''}</span>
                  </div>
                  {product.catalogueStatus === 'draft' && <p className="mt-1 text-[11px] font-bold text-amber-700">Interne : prix ou stock à compléter</p>}

                {/* Express Mode: Quick + / - Buttons on card with Staged Changes */}
                {stockMode === 'express' ? (
                  <div className="flex items-center justify-between mt-2 pt-1 border-t border-gray-50">
                    <span className="text-xs font-bold text-gray-900">
                      {stagedStockChanges[product.id] !== undefined ? stagedStockChanges[product.id] : product.stock} unités
                    </span>
                    <div className="flex items-center gap-1.5" onClick={(e) => e.stopPropagation()}>
                      <Button
                        onClick={() => {
                          const current = stagedStockChanges[product.id] !== undefined ? stagedStockChanges[product.id] : product.stock
                          const next = Math.max(0, current - 1)
                          setStagedStockChanges((prev) => ({ ...prev, [product.id]: next }))
                        }}
                        className="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 flex items-center justify-center text-gray-700 font-bold text-xs transition-colors"
                        title="Diminuer stock (-1)"
                      >
                        <Minus size={14} />
                      </Button>
                      <span className="text-xs font-bold text-blue-700 w-6 text-center">
                        {stagedStockChanges[product.id] !== undefined ? stagedStockChanges[product.id] : product.stock}
                      </span>
                      <Button
                        onClick={() => {
                          const current = stagedStockChanges[product.id] !== undefined ? stagedStockChanges[product.id] : product.stock
                          const next = current + 1
                          setStagedStockChanges((prev) => ({ ...prev, [product.id]: next }))
                        }}
                        className="w-7 h-7 rounded-lg bg-blue-600 text-white hover:bg-blue-700 flex items-center justify-center font-bold text-xs transition-colors shadow-xs"
                        title="Augmenter stock (+1)"
                      >
                        <Plus size={14} />
                      </Button>
                    </div>
                  </div>
                ) : (
                  /* Assisté Mode: Gauge + Valuation */
                  <div className="flex items-center gap-3 mt-1.5">
                    <div className="flex-1 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full transition-all"
                        style={{
                          width: `${Math.min(100, (product.stock / 80) * 100)}%`,
                          backgroundColor:
                            product.alert === 'critical'
                              ? '#F04438'
                              : product.alert === 'low'
                                ? '#F79009'
                                : '#12B76A',
                        }}
                      />
                    </div>
                    <span
                      className="text-xs font-bold"
                      style={{
                        color:
                          product.alert === 'critical'
                            ? '#F04438'
                            : product.alert === 'low'
                              ? '#F79009'
                              : '#12B76A',
                      }}
                    >
                      {product.stock} u.
                    </span>
                  </div>
                )}
              </div>

              <div className={`${catalogueDisplay === 'grid' ? 'flex items-end justify-between border-t border-gray-100 pt-2' : 'text-right flex-shrink-0'}`}>
                <p className="text-sm font-bold text-gray-900">{product.catalogueStatus === 'draft' ? 'À définir' : product.price.toLocaleString('fr-FR')}</p>
                <p className="text-[10px] text-gray-400">{product.catalogueStatus === 'draft' ? 'Prix de vente' : 'FCFA'}</p>
              </div>
            </div>
          )
        })}
        </div>

        {/* Floating Action Button "Appliquer modification" for Express Stock Changes */}
        {Object.keys(stagedStockChanges).length > 0 && (
          <div className="sticky bottom-3 left-0 right-0 px-2 z-30 animate-in slide-in-from-bottom-3 duration-200">
            <Button
              onClick={() => {
                setPendingMovementReasonSource('express')
                setMovementReasonModalOpen(true)
              }}
              className="w-full py-3.5 px-4 rounded-2xl bg-purple-600 hover:bg-purple-700 text-white font-bold text-xs flex items-center justify-between shadow-xl cursor-pointer active:scale-95 transition-transform"
            >
              <span className="flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-white/20 flex items-center justify-center font-extrabold text-[11px]">
                  {Object.keys(stagedStockChanges).length}
                </span>
                <span>Appliquer modification{Object.keys(stagedStockChanges).length > 1 ? 's' : ''} de stock</span>
              </span>
              <span className="bg-white text-purple-700 px-2.5 py-1 rounded-xl text-[11px] font-bold flex items-center gap-1">
                Motif requis <ChevronRight size={14} />
              </span>
            </Button>
          </div>
        )}

        {filtered.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3 text-gray-400">
            <Package size={48} strokeWidth={1} />
            <p className="text-sm">Aucun produit trouvé</p>
          </div>
        )}

        <div className="h-2" />
      </div>

      {/* ── MODAL FICHE PRODUIT ── */}
      {selectedProductForDetail && (
        <div
          className="absolute inset-0 z-50 flex items-end justify-center"
          style={{ backgroundColor: 'rgba(0,0,0,0.45)', backdropFilter: 'blur(2px)' }}
          onClick={() => {
            if (selectedProductForDetail.stock !== initialDetailStock) {
              setPendingMovementReasonSource('assiste')
              setMovementReasonModalOpen(true)
            } else {
              setProducts((prev) =>
                prev.map((p) => (p.id === selectedProductForDetail.id ? selectedProductForDetail : p))
              )
              setSelectedProductForDetail(null)
            }
          }}
        >
          <div
            className="lk-product-detail w-full bg-white rounded-t-3xl p-5 space-y-4 max-h-[85vh] overflow-y-auto animate-in slide-in-from-bottom duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-10 h-1 bg-gray-200 rounded-full mx-auto" />

            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div className="flex items-center gap-3">
                <ProductThumbnail product={selectedProductForDetail} className="h-14 w-14 shrink-0 rounded-2xl border border-slate-100 bg-slate-50" />
                <div>
                  <p className="lk-product-detail-eyebrow">Détail produit</p>
                  <h3 className="text-base font-bold text-gray-900">{selectedProductForDetail.name}</h3>
                  <p className="text-xs text-gray-400 mt-0.5">{selectedProductForDetail.category}</p>
                </div>
              </div>
              <Button
                onClick={() => {
                  if (selectedProductForDetail.stock !== initialDetailStock) {
                    setPendingMovementReasonSource('assiste')
                    setMovementReasonModalOpen(true)
                  } else {
                    setProducts((prev) =>
                      prev.map((p) => (p.id === selectedProductForDetail.id ? selectedProductForDetail : p))
                    )
                    setSelectedProductForDetail(null)
                  }
                }}
                className="p-1.5 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            <section className="rounded-2xl border border-slate-200 bg-slate-50 p-3" aria-labelledby="product-image-heading">
              <div className="flex items-center gap-3">
                <ProductThumbnail product={selectedProductForDetail} className="h-20 w-20 shrink-0 rounded-xl border border-slate-200 bg-white" />
                <div className="min-w-0 flex-1">
                  <h4 id="product-image-heading" className="text-xs font-bold text-slate-900">Image du produit</h4>
                  <p className="mt-0.5 text-[11px] leading-4 text-slate-500">JPEG, PNG ou WebP · 2 Mo max. L’image reste sur cet appareil jusqu’à l’ajout d’un stockage boutique.</p>
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <label htmlFor="product-image-upload" className="inline-flex min-h-9 cursor-pointer items-center gap-1.5 rounded-lg bg-blue-600 px-2.5 py-2 text-[11px] font-bold text-white transition-colors hover:bg-blue-700">
                      <Camera size={14} />
                      <span>{selectedProductForDetail.imageUrl ? 'Remplacer' : 'Ajouter une image'}</span>
                    </label>
                    {selectedProductForDetail.imageUrl && <Button onClick={() => setSelectedProductForDetail((product) => product ? { ...product, imageUrl: undefined } : null)} className="min-h-9 rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-[11px] font-bold text-slate-700">Retirer</Button>}
                  </div>
                  <Input id="product-image-upload" type="file" accept="image/jpeg,image/png,image/webp" onChange={handleProductImageSelection} className="sr-only" />
                </div>
              </div>
            </section>

            {/* Price & Stock Stats (Éditables selon la Politique Commerciale) */}
            <div className="grid grid-cols-2 gap-3">
              <div className="lk-product-detail-price bg-blue-50/70 p-3 rounded-2xl border border-blue-100">
                <label className="text-[10px] font-bold text-blue-700 uppercase">Prix de vente (FCFA)</label>
                <Input
                  type="number"
                  inputMode="numeric"
                  value={selectedProductForDetail.price}
                  onChange={(e) => {
                    const np = Number(e.target.value) || 0
                    setSelectedProductForDetail((prev) => (prev ? { ...prev, price: np } : null))
                  }}
                  className="w-full mt-1 bg-white rounded-xl px-2.5 py-1.5 text-base font-bold text-blue-900 border border-blue-200 outline-none"
                />
              </div>

              <div className="lk-product-detail-stock bg-gray-50 p-3 rounded-2xl border border-gray-100">
                <label className="text-[10px] font-bold text-gray-500 uppercase">Stock en magasin (u.)</label>
                <div className="flex items-center justify-between mt-1">
                  <Button
                    onClick={() => {
                      const ns = Math.max(0, selectedProductForDetail.stock - 1)
                      setSelectedProductForDetail((prev) => (prev ? { ...prev, stock: ns } : null))
                    }}
                    className="w-7 h-7 rounded-lg bg-gray-200 text-gray-800 font-bold text-xs active:scale-95"
                  >
                    -
                  </Button>
                  <span className="text-base font-bold text-gray-900">{selectedProductForDetail.stock}</span>
                  <Button
                    onClick={() => {
                      const ns = selectedProductForDetail.stock + 1
                      setSelectedProductForDetail((prev) => (prev ? { ...prev, stock: ns } : null))
                    }}
                    className="w-7 h-7 rounded-lg bg-blue-600 text-white font-bold text-xs active:scale-95"
                  >
                    +
                  </Button>
                </div>
              </div>
            </div>

            {selectedProductForDetail.catalogueStatus === 'draft' && (
              <div className="rounded-2xl border border-amber-200 bg-amber-50 p-3">
                <label className="text-[10px] font-bold uppercase text-amber-800">Unité de vente</label>
                <Input
                  type="text"
                  value={selectedProductForDetail.salesUnit ?? 'unité'}
                  maxLength={80}
                  onChange={(e) => setSelectedProductForDetail((prev) => prev ? { ...prev, salesUnit: e.target.value } : null)}
                  className="mt-1 w-full rounded-xl border border-amber-200 bg-white px-2.5 py-2 text-sm font-bold text-gray-900 outline-none"
                  placeholder="Ex. unité, carton, sachet"
                />
                <p className="mt-1 text-[11px] leading-4 text-amber-800">Cette information reste propre à votre boutique.</p>
              </div>
            )}

            {/* Conditionnement Modification */}
            <div className="lk-product-detail-section p-3 bg-gray-50 rounded-2xl border border-gray-100 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-gray-900">Conditionnement (Colisage) :</span>
                <span className="text-[10px] font-bold text-blue-700 bg-blue-50 px-2 py-0.5 rounded-full border border-blue-200">
                  {selectedProductForDetail.packaging || 'unite'} ({selectedProductForDetail.unitsPerPack || 1} u./colis)
                </span>
              </div>

              <div className="grid grid-cols-3 gap-1.5 pt-1">
                {[
                  { key: 'unite', label: "À l'unité", defaultPack: 1 },
                  { key: 'carton', label: '📦 Carton', defaultPack: 12 },
                  { key: 'paquet', label: '✉️ Paquet', defaultPack: 6 },
                ].map((pkg) => (
                  <Button
                    key={pkg.key}
                    onClick={() => {
                      setSelectedProductForDetail((prev) =>
                        prev
                          ? { ...prev, packaging: pkg.key as any, unitsPerPack: pkg.defaultPack }
                          : null
                      )
                    }}
                    className={`py-1.5 px-2 rounded-xl text-[10px] font-bold transition-all ${(selectedProductForDetail.packaging || 'unite') === pkg.key
                      ? 'bg-blue-600 text-white shadow-2xs'
                      : 'bg-white text-gray-700 border border-gray-200'
                      }`}
                  >
                    {pkg.label}
                  </Button>
                ))}
              </div>

              {(selectedProductForDetail.packaging === 'carton' || selectedProductForDetail.packaging === 'paquet') && (
                <div className="flex items-center justify-between pt-1">
                  <span className="text-[11px] text-gray-600 font-medium">Unités par {selectedProductForDetail.packaging} :</span>
                  <Input
                    type="number"
                    value={selectedProductForDetail.unitsPerPack || 12}
                    onChange={(e) => {
                      const u = Number(e.target.value) || 1
                      setSelectedProductForDetail((prev) => (prev ? { ...prev, unitsPerPack: u } : null))
                    }}
                    className="w-20 bg-white rounded-xl px-2 py-1 text-xs font-bold text-gray-900 border border-gray-200 text-center outline-none"
                  />
                </div>
              )}
            </div>

            {/* Politique Commerciale (Catalogue Intelligent) */}
            <div className="lk-product-detail-section p-3 bg-purple-50/70 border border-purple-100 rounded-2xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-gray-900">Politique Commerciale :</span>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-100 text-purple-700">
                  {productPolicies[selectedProductForDetail.id] === 'negotiable' ? '🏷️ Prix Négociable' : productPolicies[selectedProductForDetail.id] === 'free' ? '🆓 Prix Libre' : productPolicies[selectedProductForDetail.id] === 'on_order' ? '📦 Sur Commande' : '🔒 Prix Fixe'}
                </span>
              </div>
              <div className="grid grid-cols-2 gap-1.5 pt-1">
                {[
                  { key: 'fixed', label: '🔒 Prix Fixe' },
                  { key: 'negotiable', label: '🏷️ Négociable' },
                  { key: 'free', label: '🆓 Prix Libre' },
                  { key: 'on_order', label: '📦 Sur Commande' },
                ].map((pol) => (
                  <Button
                    key={pol.key}
                    onClick={() => {
                      setProductPolicies((prev) => ({ ...prev, [selectedProductForDetail.id]: pol.key as any }))
                      showToast?.(`Politique "${pol.label}" appliquée à ${selectedProductForDetail.name}`)
                    }}
                    className={`py-1.5 px-2 rounded-xl text-[11px] font-bold transition-all ${(productPolicies[selectedProductForDetail.id] || 'fixed') === pol.key
                      ? 'bg-purple-600 text-white shadow-2xs'
                      : 'bg-white text-gray-700 hover:bg-gray-100 border border-gray-200/60'
                      }`}
                  >
                    {pol.label}
                  </Button>
                ))}
              </div>
            </div>

            {/* Convertisseur Automatique de Conditionnement */}
            <div className="lk-product-detail-section p-3 bg-blue-50/60 border border-blue-100 rounded-2xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-blue-900">Convertisseur Colisage ➔ Unités :</span>
                <span className="text-[10px] font-bold text-blue-700">1 Carton = {selectedProductForDetail.unitsPerPack || 12} u.</span>
              </div>
              <div className="flex gap-2">
                <Input
                  type="number"
                  value={pkgCalcCartons}
                  onChange={(e) => setPkgCalcCartons(e.target.value)}
                  placeholder="Nb cartons reçus"
                  className="flex-1 bg-white rounded-xl px-3 py-2 text-xs font-bold text-gray-900 border border-gray-200 outline-none"
                />
                <Button
                  disabled={!Number(pkgCalcCartons)}
                  onClick={() => {
                    const cartons = Number(pkgCalcCartons)
                    const unitsPerCarton = selectedProductForDetail.unitsPerPack || 12
                    const totalAddedUnits = cartons * unitsPerCarton
                    const newStock = selectedProductForDetail.stock + totalAddedUnits
                    setProducts((prev) => prev.map((p) => (p.id === selectedProductForDetail.id ? { ...p, stock: newStock } : p)))
                    setSelectedProductForDetail((prev) => (prev ? { ...prev, stock: newStock } : null))
                    setPkgCalcCartons('')
                    showToast?.(`+${totalAddedUnits} unités ajoutées au stock (${cartons} cartons × ${unitsPerCarton}) !`)
                  }}
                  className="px-3 py-2 rounded-xl bg-blue-600 text-white font-bold text-xs shadow-2xs active:scale-95 disabled:opacity-40"
                >
                  Convertir & Ajouter
                </Button>
              </div>
            </div>

            {/* Quick Stock Adjuster */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between">
                <label className="text-xs font-bold text-gray-700">Ajustement rapide du stock</label>
                <Button
                  onClick={() => {
                    setMovementProduct(selectedProductForDetail)
                    setMovementModalOpen(true)
                  }}
                  className="text-xs font-bold text-purple-600 hover:text-purple-800"
                >
                  + Nouveau Mouvement Typé
                </Button>
              </div>
              <div className="lk-product-detail-adjuster flex items-center justify-between bg-gray-50 rounded-2xl p-3">
                <Button
                  onClick={() => {
                    const newStock = Math.max(0, selectedProductForDetail.stock - 1)
                    setProducts((prev) => prev.map((p) => (p.id === selectedProductForDetail.id ? { ...p, stock: newStock } : p)))
                    setSelectedProductForDetail((prev) => (prev ? { ...prev, stock: newStock } : null))
                  }}
                  className="w-10 h-10 rounded-xl bg-white border border-gray-200 flex items-center justify-center font-bold active:scale-90 transition-transform" aria-label="Retirer"
                >
                  <Minus size={16} />
                </Button>
                <span className="text-xl font-bold text-gray-900">{selectedProductForDetail.stock} u.</span>
                <Button
                  onClick={() => {
                    const newStock = selectedProductForDetail.stock + 1
                    setProducts((prev) => prev.map((p) => (p.id === selectedProductForDetail.id ? { ...p, stock: newStock } : p)))
                    setSelectedProductForDetail((prev) => (prev ? { ...prev, stock: newStock } : null))
                  }}
                  className="w-10 h-10 rounded-xl bg-blue-600 text-white flex items-center justify-center font-bold active:scale-90 transition-transform" aria-label="Ajouter"
                >
                  <Plus size={16} />
                </Button>
              </div>
            </div>

            {/* Recent Product Movement Log */}
            <div className="space-y-2">
              <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Historique des mouvements récents</p>
              <div className="divide-y divide-gray-100 bg-gray-50 rounded-2xl p-2 max-h-36 overflow-y-auto space-y-1">
                {(productMovements[selectedProductForDetail.id] || []).map((m) => (
                  <div key={m.id} className="p-2 flex items-center justify-between text-xs bg-white rounded-xl">
                    <div>
                      <p className="font-bold text-gray-900">{m.label}</p>
                      <p className="text-[10px] text-gray-400">{m.date} {m.comment ? `· ${m.comment}` : ''}</p>
                    </div>
                    <span className={`font-bold ${m.qty.startsWith('+') ? 'text-green-600' : 'text-red-600'}`}>
                      {m.qty}
                    </span>
                  </div>
                ))}
                <div className="p-2 flex items-center justify-between text-xs">
                  <div className="flex items-center gap-1.5">
                    <CheckCircle size={14} color="#12B76A" />
                    <span className="font-semibold text-gray-800">Réception livraison</span>
                  </div>
                  <span className="font-bold text-green-600">+12 u.</span>
                </div>
                <div className="p-2 flex items-center justify-between text-xs">
                  <div className="flex items-center gap-1.5">
                    <ShoppingBag size={14} color="#0050FF" />
                    <span className="font-semibold text-gray-800">Vente V-0428</span>
                  </div>
                  <span className="font-bold text-gray-500">-2 u.</span>
                </div>
              </div>
            </div>

            {selectedProductForDetail.catalogueStatus === 'draft' && (
              <Button
                onClick={() => {
                  const error = onActivateCatalogueProduct(selectedProductForDetail)
                  if (error) { showToast?.(error); return }
                  setSelectedProductForDetail(null)
                  showToast?.(`${selectedProductForDetail.name} est maintenant disponible à la vente.`)
                }}
                className="lk-product-detail-publish w-full py-3.5 rounded-2xl bg-emerald-600 text-white font-bold text-sm"
              >
                Publier dans le catalogue client
              </Button>
            )}

            <Button
              onClick={() => {
                if (selectedProductForDetail.stock !== initialDetailStock) {
                  setPendingMovementReasonSource('assiste')
                  setMovementReasonModalOpen(true)
                } else {
                  setProducts((previous) => previous.map((product) => product.id === selectedProductForDetail.id ? selectedProductForDetail : product))
                  setSelectedProductForDetail(null)
                }
              }}
              className="lk-product-detail-close w-full py-3.5 rounded-2xl bg-gray-100 text-gray-800 font-bold text-sm"
            >
              Fermer la fiche
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL ACHATS: PHOTO FACTURE ── */}
      {invoiceScanOpen && (
        <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200">
          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100">
            <Button onClick={() => setInvoiceScanOpen(false)} className="p-2 rounded-xl bg-gray-100" aria-label="Retour">
              <ChevronLeft size={18} color="#1D2939" />
            </Button>
            <div className="text-center">
              <h2 className="text-lg font-bold text-gray-900">Réception Facture Fournisseur</h2>
              <p className="text-xs text-blue-600 font-medium">Lecture intelligente OCR</p>
            </div>
            <div className="w-8" />
          </div>

          <div className="p-4 space-y-4 flex-1 flex flex-col justify-between">
            {invoiceStep === 'scanning' ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center p-8 space-y-4">
                <div className="w-20 h-20 rounded-3xl bg-blue-50 text-blue-600 flex items-center justify-center animate-pulse border-2 border-blue-200">
                  <Camera size={36} />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-gray-900">Analyse de la photo…</h3>
                  <p className="text-xs text-gray-500 mt-1 max-w-[220px]">
                    Extraction automatique des articles, quantités et prix de votre facture.
                  </p>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <div className="p-3.5 bg-blue-50 border border-blue-100 rounded-2xl flex items-center gap-3 text-xs text-blue-900">
                  <CheckCircle size={18} color="#0050FF" className="flex-shrink-0" />
                  <span>3 lignes pré-remplies détectées. Ajustez les quantités au besoin.</span>
                </div>

                <div className="space-y-3">
                  {invoiceLines.map((line) => (
                    <div key={line.id} className="p-3.5 bg-gray-50 border border-gray-100 rounded-2xl space-y-2">
                      <div className="flex items-center justify-between">
                        <Input
                          type="text"
                          value={line.name}
                          onChange={(e) => {
                            const val = e.target.value
                            setInvoiceLines((prev) => prev.map((l) => (l.id === line.id ? { ...l, name: val } : l)))
                          }}
                          className="font-bold text-sm text-gray-900 bg-transparent outline-none flex-1"
                        />
                      </div>
                      <div className="flex items-center gap-3 text-xs">
                        <div className="flex-1 bg-white px-3 py-2 rounded-xl border border-gray-200 flex items-center justify-between">
                          <span className="text-gray-400">Qté reçue :</span>
                          <Input
                            type="number"
                            value={line.qty}
                            onChange={(e) => {
                              const val = Number(e.target.value) || 1
                              setInvoiceLines((prev) => prev.map((l) => (l.id === line.id ? { ...l, qty: val } : l)))
                            }}
                            className="w-12 text-right font-bold text-gray-900 bg-transparent outline-none"
                          />
                        </div>
                        <div className="flex-1 bg-white px-3 py-2 rounded-xl border border-gray-200 flex items-center justify-between">
                          <span className="text-gray-400">Prix unitaire :</span>
                          <Input
                            type="number"
                            value={line.price}
                            onChange={(e) => {
                              const val = Number(e.target.value) || 0
                              setInvoiceLines((prev) => prev.map((l) => (l.id === line.id ? { ...l, price: val } : l)))
                            }}
                            className="w-16 text-right font-bold text-blue-600 bg-transparent outline-none"
                          />
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                <Button
                  onClick={() =>
                    setInvoiceLines((prev) => [
                      ...prev,
                      { id: Date.now().toString(), name: 'Nouveau produit', qty: 10, price: 500 },
                    ])
                  }
                  className="w-full py-3 rounded-2xl bg-gray-100 text-blue-600 font-bold text-xs hover:bg-gray-200 transition-colors"
                >
                  + Ajouter une ligne de facture
                </Button>
              </div>
            )}

            {invoiceStep === 'lines' && (
              <Button
                onClick={() => {
                  // Increment stock for matching products
                  setProducts((prev) =>
                    prev.map((p) => {
                      const match = invoiceLines.find((l) => l.name.toLowerCase() === p.name.toLowerCase())
                      return match ? { ...p, stock: p.stock + match.qty } : p
                    })
                  )
                  setInvoiceScanOpen(false)
                }}
                className="w-full py-4 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-transform shadow-lg shadow-blue-500/25 mt-4"
              >
                Valider la réception en stock
              </Button>
            )}
          </div>
        </div>
      )}

      {catalogueOpen && (
        <Dialog label="Catalogue métier" onDismiss={() => setCatalogueOpen(false)} className="h-[min(760px,90dvh)] max-w-lg overflow-hidden p-0">
          <CatalogueSelector
            sector={activeSector}
            onBack={() => setCatalogueOpen(false)}
            confirmLabel="Ajouter à ma boutique"
            onConfirm={(items, reviewAcknowledged) => {
              onCatalogueProductsSelected(items, reviewAcknowledged)
              setCatalogueOpen(false)
            }}
          />
        </Dialog>
      )}

      {/* ── MODAL: NOUVEAU PRODUIT MANUEL ── */}
      {newProductModalOpen && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
          onClick={() => setNewProductModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-blue-50 flex items-center justify-center text-blue-600">
                  <Plus size={18} />
                </div>
                <h3 className="font-bold text-gray-900 text-base">Nouveau produit manuel</h3>
              </div>
              <Button onClick={() => setNewProductModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-xs font-bold text-gray-700">Nom du produit <span className="text-red-500">*</span></label>
                <Input
                  type="text"
                  value={newProdName}
                  onChange={(e) => setNewProdName(e.target.value)}
                  placeholder="Ex: Savon Liquide 500ml"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                  autoFocus
                />
              </div>

              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs font-bold text-gray-700">Catégorie</label>
                  <Select
                    value={newProdCat}
                    onChange={(e) => setNewProdCat(e.target.value)}
                    className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-xs font-semibold outline-none"
                  >
                    {sectorCategories.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </Select>
                </div>
                <div>
                  <label className="text-xs font-bold text-gray-700">Prix vente (FCFA)</label>
                  <Input
                    type="number"
                    value={newProdPrice}
                    onChange={(e) => setNewProdPrice(e.target.value)}
                    placeholder="Ex: 850"
                    className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Quantité initiale</label>
                <Input
                  type="number"
                  value={newProdStock}
                  onChange={(e) => setNewProdStock(e.target.value)}
                  placeholder="Ex: 20"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                />
              </div>

              {/* Conditionnement options */}
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-gray-700">Conditionnement</label>
                <div className="flex bg-gray-100 p-1 rounded-xl gap-1">
                  {[
                    { key: 'unite', label: "À l'unité" },
                    { key: 'carton', label: 'Carton' },
                    { key: 'paquet', label: 'Paquet' },
                  ].map(({ key, label }) => (
                    <Button
                      key={key}
                      onClick={() => setNewProdPackaging(key as typeof newProdPackaging)}
                      className={`flex-1 py-2 rounded-lg text-xs font-bold transition-all ${newProdPackaging === key ? 'bg-white text-blue-600 shadow-sm' : 'text-gray-500'
                        }`}
                    >
                      {label}
                    </Button>
                  ))}
                </div>
              </div>

              {newProdPackaging !== 'unite' && (
                <div className="animate-in fade-in duration-200">
                  <label className="text-xs font-bold text-gray-700">
                    Unités par {newProdPackaging === 'carton' ? 'carton' : 'paquet'}
                  </label>
                  <Input
                    type="number"
                    value={newProdUnitsPerPack}
                    onChange={(e) => setNewProdUnitsPerPack(e.target.value)}
                    placeholder="Ex: 12 ou 24"
                    className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                  />
                </div>
              )}
            </div>

            <Button
              disabled={!newProdName.trim() || !newProdPrice}
              onClick={() => {
                const newP: Product = {
                  id: `p-${Date.now()}`,
                  name: newProdName.trim(),
                  price: Number(newProdPrice) || 500,
                  stock: Number(newProdStock) || 10,
                  category: newProdCat,
                  emoji: '📦',
                  packaging: newProdPackaging,
                  unitsPerPack: newProdPackaging !== 'unite' ? Number(newProdUnitsPerPack) || 12 : undefined,
                }
                setProducts((prev) => [...prev, newP])
                setNewProdName('')
                setNewProdPrice('')
                setNewProdStock('')
                setNewProductModalOpen(false)
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-all disabled:opacity-40 shadow-md"
            >
              Enregistrer le produit
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL: ENREGISTRER UN MOUVEMENT DE STOCK TYPÉ ── */}
      {movementModalOpen && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
          onClick={() => setMovementModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div>
                <h3 className="font-bold text-gray-900 text-base flex items-center gap-1.5">
                  <TrendingUp size={18} className="text-purple-600" />
                  Mouvement de Stock Typé
                </h3>
                <p className="text-xs text-purple-600 font-medium">Historisation qualifiée (Stock Assisté)</p>
              </div>
              <Button onClick={() => setMovementModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            {/* Product selection */}
            <div>
              <label className="text-xs font-bold text-gray-700">Produit concerné</label>
              <Select
                value={movementProduct?.id || ''}
                onChange={(e) => {
                  const p = products.find((prod) => prod.id === e.target.value)
                  if (p) setMovementProduct(p)
                }}
                className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-xs font-bold text-gray-900 outline-none"
              >
                {products.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.emoji} {p.name} (Stock actuel : {p.stock} u.)
                  </option>
                ))}
              </Select>
            </div>

            {/* Movement Type Grid */}
            <div className="space-y-1.5">
              <label className="text-xs font-bold text-gray-700">Motif du mouvement</label>
              <div className="grid grid-cols-2 gap-1.5 max-h-36 overflow-y-auto">
                {[
                  { key: 'entree', label: '📥 Entrée Livraison', delta: '+' },
                  { key: 'sortie', label: '📤 Sortie / Transfert', delta: '-' },
                  { key: 'retour_client', label: '↩️ Retour Client', delta: '+' },
                  { key: 'retour_fournisseur', label: '🚚 Retour Fournisseur', delta: '-' },
                  { key: 'casse', label: '💔 Casse / Perte / Vol', delta: '-' },
                  { key: 'consommation', label: '☕ Consommation Interne', delta: '-' },
                  { key: 'ajustement', label: '⚖️ Ajustement Inventaire', delta: '±' },
                ].map((m) => (
                  <Button
                    key={m.key}
                    onClick={() => setMovementType(m.key as any)}
                    className={`p-2.5 rounded-xl text-left text-xs font-bold transition-all border ${movementType === m.key
                      ? 'bg-purple-600 text-white border-purple-600 shadow-2xs'
                      : 'bg-gray-50 text-gray-700 border-gray-100 hover:bg-gray-100'
                      }`}
                  >
                    {m.label}
                  </Button>
                ))}
              </div>
            </div>

            {/* Quantity & Comment */}
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs font-bold text-gray-700">Quantité (unités)</label>
                <Input
                  type="number"
                  value={movementQty}
                  onChange={(e) => setMovementQty(e.target.value)}
                  placeholder="Ex: 10"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-xs font-bold text-gray-900 outline-none"
                />
              </div>
              <div>
                <label className="text-xs font-bold text-gray-700">Commentaire / Réf</label>
                <Input
                  type="text"
                  value={movementComment}
                  onChange={(e) => setMovementComment(e.target.value)}
                  placeholder="Ex: Bon N° 402"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-xs font-bold text-gray-900 outline-none"
                />
              </div>
            </div>

            <Button
              disabled={!movementProduct || !movementQty}
              onClick={() => {
                if (!movementProduct) return
                const qtyVal = Number(movementQty) || 10
                const isPositive = ['entree', 'retour_client'].includes(movementType)
                const isNegative = ['sortie', 'retour_fournisseur', 'casse', 'consommation'].includes(movementType)

                let newStock = movementProduct.stock
                let qtyFormatted = ''
                if (movementType === 'ajustement') {
                  newStock = qtyVal
                  qtyFormatted = `= ${qtyVal} u.`
                } else if (isPositive) {
                  newStock += qtyVal
                  qtyFormatted = `+${qtyVal} u.`
                } else if (isNegative) {
                  newStock = Math.max(0, newStock - qtyVal)
                  qtyFormatted = `-${qtyVal} u.`
                }

                // Update product stock
                setProducts((prev) => prev.map((p) => (p.id === movementProduct.id ? { ...p, stock: newStock } : p)))
                if (selectedProductForDetail?.id === movementProduct.id) {
                  setSelectedProductForDetail((prev) => (prev ? { ...prev, stock: newStock } : null))
                }

                // Log movement
                const typeLabels: Record<string, string> = {
                  entree: '📥 Entrée Livraison',
                  sortie: '📤 Sortie Interne',
                  retour_client: '↩️ Retour Client',
                  retour_fournisseur: '🚚 Retour Fournisseur',
                  casse: '💔 Casse / Vol',
                  consommation: '☕ Consommation',
                  ajustement: '⚖️ Ajustement Inventaire',
                }

                const newLog = {
                  id: `mov-${Date.now()}`,
                  type: movementType,
                  label: typeLabels[movementType] || 'Mouvement',
                  qty: qtyFormatted,
                  date: "Aujourd'hui",
                  comment: movementComment.trim(),
                }

                setProductMovements((prev) => ({
                  ...prev,
                  [movementProduct.id]: [newLog, ...(prev[movementProduct.id] || [])],
                }))

                setMovementModalOpen(false)
                setMovementComment('')
                showToast?.(`Mouvement "${typeLabels[movementType]}" enregistré pour ${movementProduct.name} (${qtyFormatted}) !`)
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-purple-600 active:scale-95 transition-all shadow-md disabled:opacity-40"
            >
              Valider le Mouvement de Stock
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

// ─── Screen: Assistant ────────────────────────────────────────────────────────

interface AssistantScreenProps {
  creditAccounts: CreditAccount[]
  setCreditAccounts: React.Dispatch<React.SetStateAction<CreditAccount[]>>
  shopName: string
}

function AssistantScreen({ creditAccounts, setCreditAccounts, shopName }: AssistantScreenProps) {
  const [messages, setMessages] = useState<ChatMessage[]>(INITIAL_MESSAGES)
  const [input, setInput] = useState('')
  const [typing, setTyping] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)

  // Carnet de Dette states
  const [carnetModalOpen, setCarnetModalOpen] = useState(false)
  const [selectedAccountForDetail, setSelectedAccountForDetail] = useState<CreditAccount | null>(null)
  const [searchDebtor, setSearchDebtor] = useState('')
  const [repaymentModalOpen, setRepaymentModalOpen] = useState(false)
  const [repaymentAmount, setRepaymentAmount] = useState('')
  const [whatsappModalOpen, setWhatsappModalOpen] = useState(false)
  const [whatsappCopied, setWhatsappCopied] = useState(false)

  const totalOutstandingDebt = creditAccounts.reduce((sum, acc) => sum + Math.max(0, getAccountBalance(acc)), 0)
  const activeDebtorsCount = creditAccounts.filter((acc) => getAccountBalance(acc) > 0).length

  const filteredDebtors = creditAccounts.filter((acc) =>
    acc.name.toLowerCase().includes(searchDebtor.toLowerCase())
  )

  const scroll = () => setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }), 50)

  useEffect(() => { scroll() }, [messages])

  const now = () => {
    const d = new Date()
    return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`
  }

  const aiReply = (q: string): string => {
    const lower = q.toLowerCase()
    if (lower.includes('dette') || lower.includes('créance') || lower.includes('crédit')) {
      return `📋 **État de votre Carnet de Dette :**\n\n• Créances totales en cours : **${totalOutstandingDebt.toLocaleString('fr-FR')} FCFA**\n• Clients débiteurs actifs : **${activeDebtorsCount}**\n\nVous pouvez gérer et relancer vos clients directement depuis le bandeau Carnet de Dette ci-dessus.`
    }
    if (lower.includes('rupture') || lower.includes('stock')) {
      return "📦 **Situation des stocks :**\n\n• 🔴 **Sucre 1kg** — critique (2 unités)\n• 🟡 **Riz Basmati 5kg** — bas (7 unités)\n• 🟡 **Café Soluble 200g** — bas (9 unités)\n\nJe vous recommande de commander du Sucre en priorité."
    }
    if (lower.includes('vente') || lower.includes('résumé')) {
      return "📊 **Résumé des ventes du jour :**\n\n• CA : **47 300 FCFA** (+12% vs hier)\n• Nombre de ventes : **23**\n• Panier moyen : **2 057 FCFA**\n• Top produit : Huile Végétale 1L\n\nExcellente journée ! Vous êtes en avance sur votre objectif hebdomadaire."
    }
    if (lower.includes('marge')) {
      return "📉 **Alerte marge :**\n\nLa marge sur **Sucre 1kg** est passée sous le seuil optimal. Le dernier achat fournisseur était à 580 FCFA — avec un prix de vente à 650 FCFA, votre marge nette est de **10.8%** seulement.\n\nSouhaitez-vous ajuster le prix de vente ?"
    }
    if (lower.includes('plus vendus') || lower.includes('populaires')) {
      return "🏆 **Top produits cette semaine :**\n\n1. 🫒 Huile Végétale 1L — 48 ventes\n2. 🌾 Riz Basmati 5kg — 32 ventes\n3. 💧 Eau Minérale 1.5L — 29 ventes\n4. 🥛 Lait Concentré — 24 ventes\n5. 🍅 Tomate Concentrée — 21 ventes"
    }
    return "Je prends note de votre demande. Voici ce que j'observe en ce moment : vos ventes sont en hausse et vos niveaux de stock globaux sont satisfaisants. Y a-t-il une information particulière que vous souhaitez approfondir ?"
  }

  const send = (text: string) => {
    if (!text.trim()) return
    const userMsg: ChatMessage = { id: Date.now().toString(), role: 'user', text: text.trim(), time: now() }
    setMessages((prev) => [...prev, userMsg])
    setInput('')
    setTyping(true)
    setTimeout(() => {
      setTyping(false)
      const reply: ChatMessage = { id: (Date.now() + 1).toString(), role: 'ai', text: aiReply(text), time: now() }
      setMessages((prev) => [...prev, reply])
    }, 1200)
  }

  const renderText = (text: string) => {
    return text.split('\n').map((line, i) => {
      const bold = line.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      return <span key={i} dangerouslySetInnerHTML={{ __html: bold + (i < text.split('\n').length - 1 ? '<br/>' : '') }} />
    })
  }

  return (
    <div className="lk-assistant flex flex-col h-full relative">
      {/* ── Entry Banner for Carnet de Dette ── */}
      <div className="lk-assistant-debt-banner bg-gradient-to-r from-blue-600 via-blue-700 to-indigo-700 px-4 py-3 border-b border-blue-800 text-white flex items-center justify-between flex-shrink-0 shadow-sm animate-cascade stagger-1">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-white/20 flex items-center justify-center flex-shrink-0">
            <BookOpen size={18} color="white" />
          </div>
          <div>
            <p className="text-[10px] text-blue-200 font-bold uppercase tracking-wider">Carnet de Dette Client</p>
            <p className="text-xs font-bold text-white">
              {totalOutstandingDebt.toLocaleString('fr-FR')} FCFA en cours • {activeDebtorsCount} comptes
            </p>
          </div>
        </div>
        <Button
          onClick={() => setCarnetModalOpen(true)}
          className="lk-assistant-debt-action px-3.5 py-1.5 rounded-xl bg-white text-blue-700 text-xs font-bold shadow-sm active:scale-95 transition-transform flex-shrink-0"
        >
          Ouvrir
        </Button>
      </div>

      {/* Messages */}
      <div className="lk-assistant-messages flex-1 overflow-y-auto px-4 py-4 space-y-4 animate-cascade stagger-2">
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'} gap-2`}
          >
            {msg.role === 'ai' && (
              <div
              className="lk-assistant-bot-avatar w-7 h-7 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5"
                style={{ background: 'linear-gradient(135deg, #0050FF, #7B2FFF)' }}
              >
                <Bot size={14} color="white" />
              </div>
            )}
            <div
              className={`lk-assistant-message max-w-[80%] rounded-2xl px-4 py-3 text-sm leading-relaxed ${msg.role === 'user'
                ? 'bg-blue-600 text-white rounded-tr-sm shadow-md shadow-blue-500/20'
                : 'bg-white border border-gray-100 text-gray-800 rounded-tl-sm shadow-sm'
                }`}
            >
              {renderText(msg.text)}
              <p
                className={`text-[10px] mt-1.5 text-right ${msg.role === 'user' ? 'text-blue-200' : 'text-gray-300'
                  }`}
              >
                {msg.time}
              </p>
            </div>
          </div>
        ))}

        {typing && (
          <div className="flex gap-2">
            <div
              className="lk-assistant-bot-avatar w-7 h-7 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ background: 'linear-gradient(135deg, #0050FF, #7B2FFF)' }}
            >
              <Bot size={14} color="white" />
            </div>
            <div className="lk-assistant-typing bg-white border border-gray-100 rounded-2xl rounded-tl-sm px-4 py-3 flex items-center gap-1">
              {[0, 1, 2].map((i) => (
                <div
                  key={i}
                  className="w-1.5 h-1.5 rounded-full bg-gray-300 animate-bounce"
                  style={{ animationDelay: `${i * 150}ms` }}
                />
              ))}
            </div>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="lk-assistant-input-bar bg-white px-4 pb-6 pt-3 border-t border-gray-100 flex-shrink-0">
        <div className="flex items-end gap-2">
          <div className="lk-assistant-input flex-1 flex items-end gap-2 bg-gray-100 rounded-2xl px-4 py-3 min-h-[48px]">
            <Input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && send(input)}
              placeholder="Posez une question..."
              className="flex-1 bg-transparent text-sm text-gray-700 placeholder-gray-400 outline-none resize-none"
            />
          </div>
          <Button className="lk-assistant-mic w-12 h-12 rounded-2xl flex items-center justify-center bg-gray-100 flex-shrink-0" aria-label="Dicter">
            <Mic size={18} color="#667085" />
          </Button>
          <Button
            onClick={() => send(input)}
            disabled={!input.trim()}
            className="lk-assistant-send w-12 h-12 rounded-2xl flex items-center justify-center flex-shrink-0 transition-all disabled:opacity-40 active:scale-95 text-white"
            aria-label="Envoyer"
          >
            <Send size={18} color="white" />
          </Button>
        </div>
      </div>

      {/* ── MODAL: CARNET DE DETTE CLIENT ── */}
      {carnetModalOpen && (
        <div className="lk-assistant-modal absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200">
          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100">
            <Button onClick={() => setCarnetModalOpen(false)} className="p-2 rounded-xl bg-gray-100" aria-label="Retour">
              <ChevronLeft size={18} color="#1D2939" />
            </Button>
            <div className="text-center">
              <h2 className="text-lg font-bold text-gray-900">Carnet de Dette</h2>
              <p className="text-xs text-blue-600 font-medium">{shopName}</p>
            </div>
            <div className="w-8" />
          </div>

          <div className="p-4 space-y-4 flex-1">
            {/* Header 2 KPIs */}
            <div className="grid grid-cols-2 gap-3">
              <div className="p-3.5 rounded-2xl bg-red-50 border border-red-100">
                <p className="text-[11px] font-bold text-red-600 uppercase tracking-wider">Total Créances</p>
                <p className="text-xl font-bold text-red-900 mt-1">
                  {totalOutstandingDebt.toLocaleString('fr-FR')} <span className="text-xs text-red-700">F</span>
                </p>
              </div>

              <div className="p-3.5 rounded-2xl bg-blue-50 border border-blue-100">
                <p className="text-[11px] font-bold text-blue-600 uppercase tracking-wider">Comptes Actifs</p>
                <p className="text-xl font-bold text-blue-900 mt-1">{activeDebtorsCount} clients</p>
              </div>
            </div>

            {/* Search */}
            <div className="flex items-center gap-2 bg-gray-100 rounded-xl px-3 py-2.5">
              <Search size={16} color="#98A2B3" />
              <Input
                value={searchDebtor}
                onChange={(e) => setSearchDebtor(e.target.value)}
                placeholder="Rechercher un client débiteur..."
                className="flex-1 bg-transparent text-sm text-gray-700 placeholder-gray-400 outline-none"
              />
            </div>

            {/* Debtor Accounts List */}
            <div className="space-y-2">
              <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Liste des comptes clients</p>
              <div className="divide-y divide-gray-100 border border-gray-100 rounded-2xl bg-white overflow-hidden shadow-sm">
                {filteredDebtors.map((acc) => {
                  const bal = getAccountBalance(acc)
                  const lastMov = acc.movements[acc.movements.length - 1]
                  return (
                    <Button
                      key={acc.id}
                      onClick={() => setSelectedAccountForDetail(acc)}
                      className="p-3.5 flex items-center justify-between hover:bg-gray-50 cursor-pointer active:bg-blue-50/50 transition-colors"
                    >
                      <div>
                        <p className="text-sm font-bold text-gray-900">{acc.name}</p>
                        <p className="text-xs text-gray-400 mt-0.5">
                          Dernière opération : {lastMov ? lastMov.date : 'Aucune'}
                        </p>
                      </div>
                      <div className="text-right">
                        <span className={`inline-block text-xs font-bold px-2.5 py-1 rounded-full ${bal > 0 ? 'bg-red-50 text-red-600' : 'bg-green-50 text-green-600'}`}>
                          {bal > 0 ? `${bal.toLocaleString('fr-FR')} FCFA dû` : 'Soldé'}
                        </span>
                      </div>
                    </Button>
                  )
                })}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── MODAL: DÉTAIL D'UN COMPTE CRÉDIT ── */}
      {selectedAccountForDetail && (
        <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-right duration-200">
          <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100">
            <Button onClick={() => setSelectedAccountForDetail(null)} className="p-2 rounded-xl bg-gray-100" aria-label="Retour">
              <ChevronLeft size={18} color="#1D2939" />
            </Button>
            <div className="text-center">
              <h2 className="text-lg font-bold text-gray-900">{selectedAccountForDetail.name}</h2>
              <p className="text-xs text-gray-400">
                {selectedAccountForDetail.phone ? `+237 ${selectedAccountForDetail.phone}` : 'Pas de numéro enregistré'}
              </p>
            </div>
            <div className="w-8" />
          </div>

          <div className="p-4 space-y-4 flex-1 flex flex-col justify-between">
            <div className="space-y-4">
              {/* Balance Card */}
              {(() => {
                const curBalance = getAccountBalance(selectedAccountForDetail)
                return (
                  <div
                    className={`rounded-2xl p-4 text-white text-center shadow-md ${curBalance > 0 ? 'bg-gradient-to-r from-red-600 to-red-700' : 'bg-gradient-to-r from-green-600 to-emerald-700'
                      }`}
                  >
                    <p className="text-xs opacity-80 mb-1 font-semibold uppercase tracking-wider">Solde du compte</p>
                    <p className="text-3xl font-bold">{curBalance.toLocaleString('fr-FR')} FCFA</p>
                    <p className="text-xs opacity-80 mt-1">
                      {curBalance > 0 ? 'Créance à recouvrer' : 'Compte totalement soldé'}
                    </p>
                  </div>
                )
              })()}

              {/* Movement History */}
              <div className="space-y-2">
                <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Historique chronologique</p>
                <div className="divide-y divide-gray-100 border border-gray-100 rounded-2xl bg-white max-h-64 overflow-y-auto">
                  {selectedAccountForDetail.movements.map((mov) => (
                    <div key={mov.id} className="p-3 flex items-center justify-between text-xs">
                      <div>
                        <div className="flex items-center gap-1.5">
                          <span
                            className={`w-2 h-2 rounded-full ${mov.type === 'sale' ? 'bg-red-500' : 'bg-green-500'}`}
                          />
                          <p className="font-bold text-gray-800">
                            {mov.type === 'sale' ? 'Vente à crédit' : 'Remboursement'}
                          </p>
                        </div>
                        <p className="text-[10px] text-gray-400 mt-0.5">{mov.date} · {mov.description}</p>
                      </div>
                      <p className={`font-bold text-sm ${mov.type === 'sale' ? 'text-red-600' : 'text-green-600'}`}>
                        {mov.type === 'sale' ? `+${mov.amount.toLocaleString('fr-FR')}` : `-${mov.amount.toLocaleString('fr-FR')}`} F
                      </p>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="space-y-2 pt-2">
              <Button
                onClick={() => setRepaymentModalOpen(true)}
                className="w-full py-3.5 rounded-2xl bg-green-600 text-white font-bold text-sm shadow-md active:scale-95 transition-transform"
              >
                Enregistrer un remboursement
              </Button>
              {selectedAccountForDetail.phone && getAccountBalance(selectedAccountForDetail) > 0 && (
                <Button
                  onClick={() => setWhatsappModalOpen(true)}
                  className="w-full py-3.5 rounded-2xl bg-emerald-50 text-emerald-700 border border-emerald-200 font-bold text-sm flex items-center justify-center gap-2 active:scale-95 transition-transform"
                >
                  <MessageSquare size={18} />
                  <span>Relancer par WhatsApp</span>
                </Button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── MODAL: ENREGISTRER UN REMBOURSEMENT ── */}
      {repaymentModalOpen && selectedAccountForDetail && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
          onClick={() => setRepaymentModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <h3 className="font-bold text-gray-900 text-base">Remboursement de {selectedAccountForDetail.name}</h3>
              <Button onClick={() => setRepaymentModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div>
              <label className="text-xs font-bold text-gray-700">Montant reçu (FCFA)</label>
              <Input
                type="number"
                value={repaymentAmount}
                onChange={(e) => setRepaymentAmount(e.target.value)}
                placeholder="Ex: 2000"
                className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                autoFocus
              />
            </div>

            <Button
              disabled={!repaymentAmount || Number(repaymentAmount) <= 0}
              onClick={() => {
                const amt = Number(repaymentAmount)
                const newMov: CreditMovement = {
                  id: `m-${Date.now()}`,
                  date: new Date().toLocaleDateString('fr-FR'),
                  type: 'repayment',
                  amount: amt,
                  description: 'Remboursement en espèces',
                }

                setCreditAccounts((prev) =>
                  prev.map((acc) => (acc.id === selectedAccountForDetail.id ? { ...acc, movements: [...acc.movements, newMov] } : acc))
                )

                setSelectedAccountForDetail((prev) => (prev ? { ...prev, movements: [...prev.movements, newMov] } : null))
                setRepaymentAmount('')
                setRepaymentModalOpen(false)
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-green-600 active:scale-95 transition-all disabled:opacity-40 shadow-md"
            >
              Valider le remboursement
            </Button>
          </div>
        </div>
      )}

      {/* ── MODAL: SIMULATEUR WHATSAPP ── */}
      {whatsappModalOpen && selectedAccountForDetail && (
        <div
          className="absolute inset-0 z-50 flex items-center justify-center px-4"
          style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
          onClick={() => setWhatsappModalOpen(false)}
        >
          <div
            className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center">
                  <MessageSquare size={18} />
                </div>
                <h3 className="font-bold text-gray-900 text-base">Rappel WhatsApp</h3>
              </div>
              <Button onClick={() => setWhatsappModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div className="bg-emerald-50 p-4 rounded-2xl border border-emerald-100 space-y-2">
              <p className="text-[11px] font-bold text-emerald-800 uppercase tracking-wider">Aperçu du message</p>
              <p className="text-xs text-emerald-950 leading-relaxed font-medium italic">
                "Bonjour {selectedAccountForDetail.name}, votre solde de crédit chez {shopName} est de {getAccountBalance(selectedAccountForDetail).toLocaleString('fr-FR')} FCFA. Merci de penser au règlement dès que possible ! 🙏"
              </p>
            </div>

            <Button
              onClick={() => {
                setWhatsappCopied(true)
                setTimeout(() => {
                  setWhatsappCopied(false)
                  setWhatsappModalOpen(false)
                }, 1200)
              }}
              className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-emerald-600 active:scale-95 transition-transform shadow-md"
            >
              {whatsappCopied ? 'Message envoyé via WhatsApp !' : 'Ouvrir WhatsApp'}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

// ─── Component: ExpenseManagementModal ───────────────────────────────────────────

function ExpenseManagementModal({
  open,
  onClose,
  expenses,
  setExpenses,
  showToast,
  shopName,
  cashSalesToday = 34500,
}: {
  open: boolean
  onClose: () => void
  expenses: Expense[]
  setExpenses: React.Dispatch<React.SetStateAction<Expense[]>>
  showToast?: (msg: string) => void
  shopName: string
  cashSalesToday?: number
}) {
  const [activeTab, setActiveTab] = useState<'saisie' | 'historique' | 'stats'>('saisie')
  const [amount, setAmount] = useState('')
  const [category, setCategory] = useState<Expense['category']>('transport')
  const [paymentSource, setPaymentSource] = useState<Expense['paymentSource']>('especes')
  const [description, setDescription] = useState('')
  const [search, setSearch] = useState('')

  if (!open) return null

  const todayDateStr = new Date().toLocaleDateString('fr-FR')
  const expensesToday = expenses
    .filter((e) => e.date === todayDateStr)
    .reduce((sum, e) => sum + e.amount, 0)

  const expensesCashToday = expenses
    .filter((e) => e.date === todayDateStr && e.paymentSource === 'especes')
    .reduce((sum, e) => sum + e.amount, 0)

  const totalExpensesMonth = expenses.reduce((sum, e) => sum + e.amount, 0)
  const theoreticalCashBalance = Math.max(0, cashSalesToday - expensesCashToday)

  const filteredExpenses = expenses.filter(
    (e) =>
      e.description.toLowerCase().includes(search.toLowerCase()) ||
      e.category.toLowerCase().includes(search.toLowerCase())
  )

  const handleAddExpense = () => {
    if (!amount || Number(amount) <= 0) return
    const newExp: Expense = {
      id: `exp-${Date.now()}`,
      date: new Date().toLocaleDateString('fr-FR'),
      timestamp: Date.now(),
      amount: Number(amount),
      category,
      paymentSource,
      description: description.trim() || EXPENSE_CATEGORIES.find((c) => c.key === category)?.label || 'Dépense',
    }

    setExpenses((prev) => [newExp, ...prev])
    setAmount('')
    setDescription('')
    showToast?.(`Dépense de ${Number(amount).toLocaleString('fr-FR')} FCFA enregistrée !`)
    setActiveTab('historique')
  }

  const handleDeleteExpense = (id: string) => {
    setExpenses((prev) => prev.filter((e) => e.id !== id))
    showToast?.('Dépense supprimée du registre.')
  }

  return (
    <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3.5 border-b border-slate-100 sticky top-0 bg-white/95 backdrop-blur-md z-10">
        <Button onClick={onClose} className="p-2 rounded-2xl bg-slate-100 hover:bg-slate-200 transition-colors" aria-label="Retour">
          <ChevronLeft size={18} className="text-slate-800" />
        </Button>
        <div className="text-center">
          <h2 className="text-base font-extrabold text-slate-900">Gestion des Dépenses</h2>
          <p className="text-[11px] text-rose-600 font-bold">{shopName} · Sorties & OPEX</p>
        </div>
        <Button onClick={onClose} className="p-2 rounded-2xl bg-slate-100 text-slate-500 hover:bg-slate-200" aria-label="Fermer">
          <X size={18} />
        </Button>
      </div>

      <div className="p-4 space-y-4 flex-1">
        {/* Top 3 KPIs */}
        <div className="grid grid-cols-3 gap-2 animate-cascade stagger-1">
          <div className="p-3 rounded-2xl bg-rose-50 border border-rose-100/80 shadow-2xs">
            <p className="text-[10px] font-bold text-rose-600 uppercase tracking-wider">Dépenses Jour</p>
            <p className="text-sm font-extrabold text-rose-950 mt-0.5">{expensesToday.toLocaleString('fr-FR')} F</p>
          </div>
          <div className="p-3 rounded-2xl bg-indigo-50 border border-indigo-100/80 shadow-2xs">
            <p className="text-[10px] font-bold text-indigo-600 uppercase tracking-wider">Sorties Cash</p>
            <p className="text-sm font-extrabold text-indigo-950 mt-0.5">-{expensesCashToday.toLocaleString('fr-FR')} F</p>
          </div>
          <div className="p-3 rounded-2xl bg-amber-50 border border-amber-100/80 shadow-2xs">
            <p className="text-[10px] font-bold text-amber-700 uppercase tracking-wider">Cash Théorique</p>
            <p className="text-sm font-extrabold text-amber-950 mt-0.5">{theoreticalCashBalance.toLocaleString('fr-FR')} F</p>
          </div>
        </div>

        {/* Tab Switcher */}
        <div className="flex bg-slate-100 p-1 rounded-2xl border border-slate-200/60 animate-cascade stagger-2">
          {[
            { key: 'saisie', label: '➕ Saisie' },
            { key: 'historique', label: '📜 Registre' },
            { key: 'stats', label: '📊 Ventilation' },
          ].map(({ key, label }) => (
            <Button
              key={key}
              onClick={() => setActiveTab(key as typeof activeTab)}
              className={`flex-1 py-2 rounded-xl text-xs font-extrabold transition-all cursor-pointer ${activeTab === key ? 'bg-white text-indigo-600 shadow-2xs' : 'text-slate-500 hover:text-slate-800'
                }`}
            >
              {label}
            </Button>
          ))}
        </div>

        {/* ── TAB 1: SAISIE RAPIDE DE DÉPENSE ── */}
        {activeTab === 'saisie' && (
          <div className="space-y-4 bg-slate-50 p-4 rounded-3xl border border-slate-200/80 shadow-2xs animate-cascade stagger-3">
            <div className="flex items-center gap-2 border-b border-slate-200/60 pb-3">
              <div className="w-8 h-8 rounded-xl bg-rose-100 text-rose-700 flex items-center justify-center font-bold">
                💸
              </div>
              <div>
                <h3 className="font-extrabold text-slate-900 text-sm">Enregistrer une Sortie de Caisse</h3>
                <p className="text-[11px] text-slate-500 font-medium">Saisie rapide en moins de 15 secondes</p>
              </div>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-xs font-bold text-slate-700">Montant de la dépense (FCFA) <span className="text-rose-500">*</span></label>
                <Input
                  type="number"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="Ex: 2500"
                  className="w-full mt-1 bg-white rounded-2xl px-4 py-3.5 text-base font-extrabold text-slate-900 outline-none border border-slate-200 focus:border-indigo-600 transition-all shadow-2xs"
                  autoFocus
                />
              </div>

              {/* Category Selector Grid */}
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700">Catégorie de la dépense</label>
                <div className="grid grid-cols-2 gap-2 max-h-48 overflow-y-auto">
                  {EXPENSE_CATEGORIES.map((cat) => {
                    const isSelected = category === cat.key
                    return (
                      <Button
                        key={cat.key}
                        onClick={() => setCategory(cat.key)}
                        className={`p-2.5 rounded-2xl text-left border transition-all flex items-center gap-2 cursor-pointer ${isSelected
                          ? 'border-indigo-600 bg-indigo-50/80 text-indigo-950 font-extrabold shadow-2xs'
                          : 'border-slate-200/80 bg-white text-slate-700 hover:bg-slate-100'
                          }`}
                      >
                        <span className="text-lg">{cat.emoji}</span>
                        <span className="text-[11px] leading-tight truncate">{cat.label}</span>
                      </Button>
                    )
                  })}
                </div>
              </div>

              {/* Payment Source */}
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700">Source du paiement</label>
                <div className="grid grid-cols-3 gap-2">
                  {[
                    { key: 'especes', label: '💵 Caisse Cash' },
                    { key: 'mobile_money', label: '📱 Mobile Money' },
                    { key: 'personnel', label: '👤 Patron / Hors Caisse' },
                  ].map((src) => (
                    <Button
                      key={src.key}
                      onClick={() => setPaymentSource(src.key as typeof paymentSource)}
                      className={`p-2 rounded-2xl border text-center transition-all cursor-pointer ${paymentSource === src.key
                        ? 'border-indigo-600 bg-indigo-600 text-white font-extrabold shadow-xs'
                        : 'border-slate-200/80 bg-white text-slate-700 hover:bg-slate-100'
                        }`}
                    >
                      <p className="text-[11px] leading-tight">{src.label}</p>
                    </Button>
                  ))}
                </div>
              </div>

              {/* Motif / Description */}
              <div>
                <label className="text-xs font-bold text-slate-700">Motif ou libellé (Optionnel)</label>
                <Input
                  type="text"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Ex: Course taxi livraison riz, facture électricité..."
                  className="w-full mt-1 bg-white rounded-2xl px-3.5 py-3 text-xs font-semibold text-slate-900 outline-none border border-slate-200"
                />
              </div>
            </div>

            <Button
              disabled={!amount || Number(amount) <= 0}
              onClick={handleAddExpense}
              className="w-full py-4 rounded-2xl text-white font-extrabold text-sm bg-gradient-to-r from-rose-600 to-indigo-600 active:scale-[0.98] transition-all disabled:opacity-40 shadow-glow-indigo mt-2 flex items-center justify-center gap-2 cursor-pointer"
            >
              <Check size={18} />
              <span>Valider la dépense de {amount ? `${Number(amount).toLocaleString('fr-FR')} FCFA` : ''}</span>
            </Button>
          </div>
        )}

        {/* ── TAB 2: HISTORIQUE ET REGISTRE ── */}
        {activeTab === 'historique' && (
          <div className="space-y-3 animate-cascade stagger-3">
            {/* Search input */}
            <div className="flex items-center gap-2 bg-slate-100 rounded-2xl px-3 py-2.5 border border-slate-200/70">
              <Search size={16} className="text-slate-400" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Rechercher une dépense..."
                className="flex-1 bg-transparent text-xs text-slate-800 placeholder-slate-400 outline-none font-semibold"
              />
            </div>

            <div className="divide-y divide-slate-100 border border-slate-200/80 rounded-2xl bg-white overflow-hidden shadow-2xs">
              {filteredExpenses.length === 0 ? (
                <div className="p-8 text-center space-y-2">
                  <p className="text-3xl">🧾</p>
                  <p className="text-xs text-slate-500 font-medium">Aucune dépense enregistrée</p>
                </div>
              ) : (
                filteredExpenses.map((exp) => {
                  const catMeta = EXPENSE_CATEGORIES.find((c) => c.key === exp.category) || EXPENSE_CATEGORIES[7]
                  return (
                    <div key={exp.id} className="p-3.5 flex items-center justify-between hover:bg-slate-50 transition-colors">
                      <div className="flex items-center gap-3">
                        <span className="text-2xl">{catMeta.emoji}</span>
                        <div>
                          <p className="text-xs font-extrabold text-slate-900">{exp.description}</p>
                          <div className="flex items-center gap-2 mt-0.5 text-[10px] text-slate-400">
                            <span>{exp.date}</span>
                            <span>·</span>
                            <span className="font-semibold text-slate-600">
                              {exp.paymentSource === 'especes' ? '💵 Cash' : exp.paymentSource === 'mobile_money' ? '📱 MoMo' : '👤 Patron'}
                            </span>
                          </div>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 text-right">
                        <span className="text-sm font-extrabold text-rose-600">-{exp.amount.toLocaleString('fr-FR')} F</span>
                        <Button
                          onClick={() => handleDeleteExpense(exp.id)}
                          className="p-1.5 rounded-xl text-slate-300 hover:text-rose-600 hover:bg-rose-50 transition-colors cursor-pointer"
                          title="Supprimer la dépense"
                        >
                          <Trash2 size={14} />
                        </Button>
                      </div>
                    </div>
                  )
                })
              )}
            </div>

            {/* Export Action */}
            <div className="flex gap-2 pt-2">
              <Button
                onClick={() => showToast?.("Journal des dépenses généré en PDF !")}
                className="flex-1 py-3 rounded-2xl bg-indigo-50 border border-indigo-200 text-indigo-700 font-extrabold text-xs flex items-center justify-center gap-1.5 cursor-pointer"
              >
                <FileText size={15} /> Export PDF
              </Button>
              <Button
                onClick={() => showToast?.("Récapitulatif des dépenses partagé sur WhatsApp !")}
                className="flex-1 py-3 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-700 font-extrabold text-xs flex items-center justify-center gap-1.5 cursor-pointer"
              >
                <MessageSquare size={15} /> Partager WhatsApp
              </Button>
            </div>
          </div>
        )}

        {/* ── TAB 3: VENTILATION ET STATISTIQUES ── */}
        {activeTab === 'stats' && (
          <div className="space-y-4 animate-cascade stagger-3">
            <div className="bg-slate-900 text-white rounded-3xl p-4 space-y-3 shadow-md border border-slate-800">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Cumul des dépenses du mois</p>
                  <p className="text-xl font-extrabold text-white mt-0.5">{totalExpensesMonth.toLocaleString('fr-FR')} FCFA</p>
                </div>
                <span className="px-2.5 py-1 rounded-full bg-rose-500/20 text-rose-300 text-[10px] font-bold border border-rose-500/30">
                  Ratio / CA : 8.5%
                </span>
              </div>
            </div>

            {/* Distribution list */}
            <div className="space-y-2">
              <p className="text-xs font-extrabold text-slate-800">Ventilation par Catégorie</p>
              <div className="space-y-2 bg-white rounded-3xl p-4 border border-slate-200/80 shadow-2xs">
                {EXPENSE_CATEGORIES.map((cat) => {
                  const catTotal = expenses
                    .filter((e) => e.category === cat.key)
                    .reduce((sum, e) => sum + e.amount, 0)
                  const pct = totalExpensesMonth > 0 ? Math.round((catTotal / totalExpensesMonth) * 100) : 0
                  if (catTotal === 0 && pct === 0) return null
                  return (
                    <div key={cat.key} className="space-y-1">
                      <div className="flex items-center justify-between text-xs">
                        <div className="flex items-center gap-1.5">
                          <span>{cat.emoji}</span>
                          <span className="font-bold text-slate-800">{cat.label}</span>
                        </div>
                        <span className="font-extrabold text-slate-900">{catTotal.toLocaleString('fr-FR')} F ({pct}%)</span>
                      </div>
                      <div className="w-full h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div className="h-full rounded-full bg-indigo-600 transition-all" style={{ width: `${pct}%` }} />
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

// ─── App Shell ────────────────────────────────────────────────────────────────

function MainAppShell({
  tenantId,
  shopName,
  shopCity,
  sector,
  catalogueSelections,
  catalogueReviewAcknowledged,
  onResetOnboarding,
}: {
  tenantId: string
  shopName: string
  shopCity: string
  sector: string
  catalogueSelections: CatalogueItem[]
  catalogueReviewAcknowledged: boolean
  onResetOnboarding: () => void
}) {
  const [tab, setTab] = useState<Tab>('vente')
  const prevTabRef = useRef<Tab>(tab)
  const [tabDirection, setTabDirection] = useState<'right' | 'left'>('right')

  const TAB_ORDER: Record<Tab, number> = {
    accueil: 0,
    vente: 1,
    stock: 2,
    assistant: 3,
  }

  const changeTab = (newTab: Tab) => {
    if (newTab === tab) return
    const prevIdx = TAB_ORDER[tab] ?? 0
    const newIdx = TAB_ORDER[newTab] ?? 0
    setTabDirection(newIdx > prevIdx ? 'right' : 'left')
    prevTabRef.current = tab
    setTab(newTab)
  }

  const [initialTenantCatalogue] = useState(() => {
    const saved = loadTenantCatalogue(tenantId)
    if (saved) return saved
    const selection = selectCatalogueReferences(tenantId, [], catalogueSelections, undefined, catalogueReviewAcknowledged)
    return { products: selection.products, events: selection.events }
  })
  const [tenantCatalogueProducts, setTenantCatalogueProducts] = useState<TenantCatalogueProduct[]>(initialTenantCatalogue.products)
  const [tenantCatalogueEvents, setTenantCatalogueEvents] = useState<TenantCatalogueEvent[]>(initialTenantCatalogue.events)

  // The central selection is a local draft. Only active products reach the sale surface.
  const [products, setProducts] = useState<Product[]>(() => [
    ...(sector === 'Épicerie' ? PRODUCTS : []),
    ...initialTenantCatalogue.products.map(productFromTenantCatalogue),
  ])
  useEffect(() => {
    saveTenantCatalogue(tenantId, tenantCatalogueProducts, tenantCatalogueEvents)
  }, [tenantCatalogueEvents, tenantCatalogueProducts, tenantId])
  const [creditAccounts, setCreditAccounts] = useState<CreditAccount[]>(INITIAL_CREDIT_ACCOUNTS)
  const [expenses, setExpenses] = useState<Expense[]>(INITIAL_EXPENSES)
  const [expenseManagementModalOpen, setExpenseManagementModalOpen] = useState(false)

  // Loyalty & Promotions domain state
  const [customers, setCustomers] = useState<CustomerLoyalty[]>(INITIAL_CUSTOMERS)
  const [coupons, setCoupons] = useState<PromotionCoupon[]>(INITIAL_COUPONS)
  const [loyaltySettings, setLoyaltySettings] = useState<LoyaltySettings>(INITIAL_LOYALTY_SETTINGS)
  const [loyaltyPromotionsModalOpen, setLoyaltyPromotionsModalOpen] = useState(false)
  const [loyaltyTab, setLoyaltyTab] = useState<'customers' | 'coupons' | 'rules' | 'marketing'>('customers')
  const [newCouponCode, setNewCouponCode] = useState('')
  const [newCouponType, setNewCouponType] = useState<'percent' | 'fixed'>('percent')
  const [newCouponVal, setNewCouponVal] = useState('')
  const [newCouponMinOrder, setNewCouponMinOrder] = useState('5000')
  const [createCouponModalOpen, setCreateCouponModalOpen] = useState(false)

  const [pointsAdjustCustomer, setPointsAdjustCustomer] = useState<CustomerLoyalty | null>(null)
  const [pointsAdjustAmount, setPointsAdjustAmount] = useState('')
  const [pointsAdjustType, setPointsAdjustType] = useState<'add' | 'sub'>('add')
  const [pointsAdjustModalOpen, setPointsAdjustModalOpen] = useState(false)

  // Enterprise Info state
  const [enterpriseInfo, setEnterpriseInfo] = useState<EnterpriseInfo>({
    companyName: 'Groupe Lynkstor Sarl',
    niu: 'M051212345678A',
    rccm: 'RC/DLA/2023/B/1234',
    headOfficeCity: shopCity || 'Douala',
    subscriptionPlan: 'Entreprise Multi-boutiques',
  })

  // Settings hub states
  const [settingsModalOpen, setSettingsModalOpen] = useState(false)
  const [workspaceModalOpen, setWorkspaceModalOpen] = useState(false)
  const [activeWorkspaceRole, setActiveWorkspaceRole] = useState<WorkspaceRole>('proprietaire')
  const [commercePolicy, setCommercePolicy] = useState<CommercePolicy>(DEFAULT_COMMERCE_POLICY)
  const [catalogueDisplay, setCatalogueDisplay] = useState<'grid' | 'list'>(() => {
    try { return localStorage.getItem('lynkstor.catalogue.display.v1') === 'list' ? 'list' : 'grid' }
    catch { return 'grid' }
  })
  const [showInternalCatalogueImages, setShowInternalCatalogueImages] = useState(() => {
    try { return localStorage.getItem('lynkstor.catalogue.internal-images.v1') !== 'hidden' }
    catch { return true }
  })
  const [customerOrdersOpen, setCustomerOrdersOpen] = useState(false)

  // New module modals (Carnet de dette, Client PWA USSD, Plans d'abonnement)
  const [creditLedgerModalOpen, setCreditLedgerModalOpen] = useState(false)
  const [repaymentAccount, setRepaymentAccount] = useState<CreditAccount | null>(null)
  const [repaymentAmountInput, setRepaymentAmountInput] = useState('')
  const [repaymentModalOpen, setRepaymentModalOpen] = useState(false)
  const [whatsappReminderAccount, setWhatsappReminderAccount] = useState<CreditAccount | null>(null)
  const [whatsappReminderModalOpen, setWhatsappReminderModalOpen] = useState(false)

  const [clientPwaModalOpen, setClientPwaModalOpen] = useState(false)
  const [clientPwaStep, setClientPwaStep] = useState<'catalog' | 'cart' | 'checkout' | 'ussd_push' | 'confirmed'>('catalog')
  const [clientPwaCart, setClientPwaCart] = useState<CartItem[]>([])
  const [clientPwaPayMethod, setClientPwaPayMethod] = useState<'caisse' | 'ussd'>('ussd')
  const [clientPwaPin, setClientPwaPin] = useState('')

  // Enhanced PWA Client States (Navigation 4 Onglets, Mode Hybride, Répertoire, Historique, Consentements)
  const [clientPwaTab, setClientPwaTab] = useState<'catalog' | 'repertoire' | 'historique' | 'autorisations'>('catalog')
  const [clientPwaOrderMode, setClientPwaOrderMode] = useState<'scan_achat' | 'precommande'>('scan_achat')
  const [clientPwaTransportMode, setClientPwaTransportMode] = useState<'cloud' | 'catalogue_local'>('cloud')
  const [clientPwaTheme, setClientPwaTheme] = useState<'light' | 'dark'>(() => {
    try { return localStorage.getItem('lynkstor.client.theme.v1') === 'light' ? 'light' : 'dark' }
    catch { return 'dark' }
  })
  const [clientPwaAboutOpen, setClientPwaAboutOpen] = useState(false)
  const [clientPwaCustomerName, setClientPwaCustomerName] = useState('Jean Marc')
  const [clientPwaCustomerPhone, setClientPwaCustomerPhone] = useState('699112233')
  const [clientPwaConsentOptIn, setClientPwaConsentOptIn] = useState(false)
  const [clientPwaBarcodeScannerOpen, setClientPwaBarcodeScannerOpen] = useState(false)

  // Visited Shops for PWA Répertoire
  const [clientPwaVisitedShops, setClientPwaVisitedShops] = useState([
    { id: 'shop-active', name: shopName, city: shopCity, sector: sector, lastVisit: "Aujourd'hui à 14:20", points: 120, promo: 'Offre -10% sur les huiles', active: true },
    { id: 'shop-2', name: 'Supérette Bastos', city: 'Yaoundé', sector: 'Supermarché', lastVisit: 'Il y a 3 jours', points: 45, promo: 'Points x2 ce week-end', active: false },
    { id: 'shop-3', name: 'Boulangerie Délices', city: 'Douala', sector: 'Boulangerie', lastVisit: 'Il y a 1 semaine', points: 80, promo: 'Brioche offerte > 3000 F', active: false },
  ])

  // Customer Orders & Digital Receipts for PWA Historique
  const [clientPwaOrders, setClientPwaOrders] = useState<ClientPwaOrder[]>([
    {
      id: 'CMD-8492',
      shopName: shopName,
      date: "Aujourd'hui à 14:15",
      status: 'Commande traitée (démo)',
      payStatus: 'simulation',
      payMethod: 'Demande USSD (simulation)',
      fulfillmentStatus: 'terminee',
      items: [
        { name: 'Huile Végétale 1L', qty: 2, price: 1350 },
        { name: 'Riz Basmati 5kg', qty: 1, price: 3800 },
      ],
      total: 6500,
    },
    {
      id: 'CMD-8104',
      shopName: 'Supérette Bastos',
      date: '25/07/2026',
      status: 'Commande traitée (démo)',
      payStatus: 'non_requis',
      payMethod: 'Espèces à la caisse',
      fulfillmentStatus: 'terminee',
      items: [
        { name: 'Sucre 1kg', qty: 3, price: 550 },
      ],
      total: 1650,
    },
  ])

  // Per-shop Marketing Consent dictionary
  const [clientPwaConsents, setClientPwaConsents] = useState<Record<string, boolean>>({
    'shop-active': true,
    'shop-2': false,
    'shop-3': true,
  })

  const clientPwaActiveShop = clientPwaVisitedShops.find((shop) => shop.active) ?? clientPwaVisitedShops[0]
  const setClientPwaThemePreference = (nextTheme: 'light' | 'dark') => {
    setClientPwaTheme(nextTheme)
    try { localStorage.setItem('lynkstor.client.theme.v1', nextTheme) } catch { /* Preference conservée pour la session. */ }
  }
  const setCatalogueDisplayPreference = (nextDisplay: 'grid' | 'list') => {
    setCatalogueDisplay(nextDisplay)
    try { localStorage.setItem('lynkstor.catalogue.display.v1', nextDisplay) } catch { /* Préférence conservée pour la session. */ }
  }
  const setInternalCatalogueImagesPreference = (showImages: boolean) => {
    setShowInternalCatalogueImages(showImages)
    try { localStorage.setItem('lynkstor.catalogue.internal-images.v1', showImages ? 'shown' : 'hidden') } catch { /* Préférence conservée pour la session. */ }
  }
  const queueClientPwaOrder = (payStatus: ClientPwaOrder['payStatus'], payMethod: string) => {
    const isLocalDraft = clientPwaTransportMode === 'catalogue_local'
    const order: ClientPwaOrder = {
      id: `CMD-${Math.floor(1000 + Math.random() * 9000)}`,
      shopName,
      date: "À l'instant",
      status: isLocalDraft ? 'À envoyer — local' : 'Nouvelle',
      fulfillmentStatus: isLocalDraft ? 'a_envoyer' : 'nouvelle',
      payStatus,
      payMethod,
      customerName: clientPwaCustomerName.trim().slice(0, 80),
      customerPhone: clientPwaCustomerPhone.trim().slice(0, 24) || undefined,
      items: clientPwaCart.map((item) => ({ name: item.product.name, qty: item.qty, price: item.product.price })),
      total: clientPwaCart.reduce((sum, item) => sum + item.product.price * item.qty, 0),
    }
    setClientPwaOrders((orders) => [order, ...orders])
  }

  const [subscriptionPlansModalOpen, setSubscriptionPlansModalOpen] = useState(false)
  const [activeSettingsSection, setActiveSettingsSection] = useState<'index' | 'appearance' | 'catalogue' | 'enterprise' | 'sector' | 'devices' | 'modules' | 'sync' | 'commerce'>('index')
  const [editEnterpriseCompanyName, setEditEnterpriseCompanyName] = useState('')
  const [editEnterpriseNiu, setEditEnterpriseNiu] = useState('')
  const [editEnterpriseRccm, setEditEnterpriseRccm] = useState('')
  const [editEnterpriseHeadCity, setEditEnterpriseHeadCity] = useState('')

  // Post-Sale Receipt & WhatsApp Action Modal state
  const [postSaleReceiptModalOpen, setPostSaleReceiptModalOpen] = useState(false)
  const [lastCompletedSale, _setLastCompletedSale] = useState<{
    id: string
    total: number
    paymentMode: string
    customerName?: string
    customerPhone?: string
    items: { name: string; qty: number; price: number }[]
  }>({
    id: 'V-0428',
    total: 6500,
    paymentMode: 'Espèces',
    customerName: 'Jean Pierre',
    items: [
      { name: 'Huile Végétale 1L', qty: 2, price: 1500 },
      { name: 'Sucre 1kg', qty: 5, price: 700 },
    ],
  })

  // Supplier Order & Informal WhatsApp Direct Channel (§6.7 / §6.7bis Arch. Tech)
  const [supplierOrderModalOpen, setSupplierOrderModalOpen] = useState(false)
  const [supplierOrderType, setSupplierOrderType] = useState<'lynkstor_digital' | 'whatsapp_informal'>('whatsapp_informal')
  const [supplierWholesalerName, setSupplierWholesalerName] = useState('Grossiste Socapalm (Marché Central)')
  const [supplierWholesalerPhone, setSupplierWholesalerPhone] = useState('699887766')
  const [supplierOrderItems, setSupplierOrderItems] = useState<{ id: string; name: string; qty: number; price: number }[]>([
    { id: '1', name: 'Sucre 1kg', qty: 30, price: 520 },
    { id: '2', name: 'Huile Végétale 1L', qty: 24, price: 1200 },
  ])

  // Event Sourcing Log Inspector (§5.1 Arch. Tech)
  const [eventLogInspectorOpen, setEventLogInspectorOpen] = useState(false)
  const [eventLogList, _setEventLogList] = useState([
    { id: 'EVT-8942', type: 'VenteValidee', payload: 'Vente V-0428 (3 art. · 6 500 FCFA)', date: "Aujourd'hui à 14:15", syncStatus: 'Synchronisé' },
    { id: 'EVT-8941', type: 'StockReceptionne', payload: 'Facture #FAC-991 (+24 u. Huile Végétale)', date: "Aujourd'hui à 11:30", syncStatus: 'Synchronisé' },
    { id: 'EVT-8940', type: 'MouvementCredit', payload: 'Vente à crédit Jean Pierre (+2 000 FCFA)', date: 'Hier à 17:40', syncStatus: 'Synchronisé' },
    { id: 'EVT-8939', type: 'PersonnelReaffecte', payload: 'Amadou M. affecté à Boutique Douala (Caisse)', date: '26/07/2026', syncStatus: 'Synchronisé' },
    { id: 'EVT-8938', type: 'ProduitCree', payload: 'Nouveau produit : Riz Basmati 5kg', date: '25/07/2026', syncStatus: 'Synchronisé' },
  ])

  // Feature Toggles state for Modules activés (Restructuré par Forfait Tarifaire §Lynkstor Prospection)
  const [enabledModules, setEnabledModules] = useState<Record<string, boolean>>({
    // Starter (Gratuit)
    expressPos: true,
    barcodeScanner: true,
    creditSale: true,
    offlineMode: true,
    expenseCashEntry: true,
    // Essential (Développement)
    cloudBackupSync: true,
    cashClosureReportZ: true,
    expenseCategoryLedger: true,
    multiPackPackaging: true,
    // Pro (Croissance)
    aiAssistant: true,
    invoiceOcr: true,
    expenseNetProfitAnalysis: true,
    loyaltyPromotions: true,
    // Business (Entreprise)
    multiShopManagement: true,
    expenseMultiShopApproval: true,
    multiUserPermissions: true,
    pushUssdMobileMoney: true,
  })
  const [selectedPlanTab, setSelectedPlanTab] = useState<'starter' | 'essential' | 'pro' | 'business'>('essential')

  // Sync state for Synchronisation locale
  const [isSyncing, setIsSyncing] = useState(false)
  const [lastSyncTime, setLastSyncTime] = useState("Aujourd'hui à 15:42")

  // Module 7 & 8 states: Reporting & Clôture de caisse
  const [reportingModalOpen, setReportingModalOpen] = useState(false)
  const [reportingZReportOpen, setReportingZReportOpen] = useState(false)
  const [reportingRange, setReportingRange] = useState<'jour' | 'semaine' | 'mois'>('jour')
  const [reportingScope, setReportingScope] = useState<'active' | 'all'>('active')

  const [cashClosureModalOpen, setCashClosureModalOpen] = useState(false)
  const [cashBill10k, setCashBill10k] = useState('8')
  const [cashBill5k, setCashBill5k] = useState('5')
  const [cashBill2k, setCashBill2k] = useState('8')
  const [cashBill1k, setCashBill1k] = useState('4')
  const [cashCoins, setCashCoins] = useState('2500')

  // Multi-Boutique & Owner Space states
  const [menuModalOpen, setMenuModalOpen] = useState(false)
  const [ownerSpaceOpen, setOwnerSpaceOpen] = useState(false)
  const [shops, setShops] = useState<ShopOwnerItem[]>(() => getInitialShops(shopName, shopCity))
  const [selectedShopId, setSelectedShopId] = useState<string | null>(null)

  // Mini-parcours Nouvelle Boutique state
  const [createShopModalOpen, setCreateShopModalOpen] = useState(false)
  const [createShopStep, setCreateShopStep] = useState<1 | 2 | 3 | 4>(1)
  const [newShopName, setNewShopName] = useState('')
  const [newShopCity, setNewShopCity] = useState('')
  const [newShopSector, setNewShopSector] = useState('Épicerie')
  const [newShopCategories, setNewShopCategories] = useState<string[]>(SECTORS[0].categories)



  // Staff management states
  const [addStaffModalOpen, setAddStaffModalOpen] = useState(false)
  const [newStaffName, setNewStaffName] = useState('')
  const [newStaffRole, setNewStaffRole] = useState<'caisse' | 'stock' | 'supervision'>('caisse')

  const [editingStaff, setEditingStaff] = useState<{ staff: ShopStaff; fromShopId: string } | null>(null)
  const [editStaffRole, setEditStaffRole] = useState<'caisse' | 'stock' | 'supervision'>('caisse')
  const [editStaffShopId, setEditStaffShopId] = useState<string>('')

  const syncTransport = useSyncTransport()

  // Toast notification state
  const [toastMessage, setToastMessage] = useState<string | null>(null)

  const showToast = (msg: string) => {
    setToastMessage(msg)
    setTimeout(() => setToastMessage(null), 2500)
  }

  const addSelectedCatalogueProducts = (items: CatalogueItem[], reviewAcknowledged: boolean) => {
    try {
      const result = selectCatalogueReferences(tenantId, tenantCatalogueProducts, items, undefined, reviewAcknowledged)
      setTenantCatalogueProducts(result.products)
      setTenantCatalogueEvents((previous) => [...previous, ...result.events])
      setProducts((previous) => [...previous, ...result.added.map(productFromTenantCatalogue)])
      if (result.added.length) showToast(`${result.added.length} fiche${result.added.length > 1 ? 's' : ''} ajoutée${result.added.length > 1 ? 's' : ''} à votre catalogue.`)
      else showToast('Ces produits sont déjà dans votre catalogue.')
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Impossible d’ajouter ces produits.')
    }
  }

  const activateCatalogueProduct = (product: Product): string | null => {
    if (!product.tenantCatalogueProduct) return null
    try {
      const { product: configured, event } = configureTenantCatalogueProduct(product.tenantCatalogueProduct, {
        sellingPrice: product.price,
        initialStock: product.stock,
        salesUnit: product.salesUnit ?? 'unité',
      })
      setTenantCatalogueProducts((previous) => previous.map((entry) => entry.id === configured.id ? configured : entry))
      setTenantCatalogueEvents((previous) => [...previous, event])
      setProducts((previous) => previous.map((entry) => entry.id === product.id
        ? {
            ...entry,
            price: configured.sellingPrice ?? entry.price,
            stock: configured.initialStock ?? entry.stock,
            salesUnit: configured.salesUnit ?? entry.salesUnit,
            catalogueStatus: configured.status,
            tenantCatalogueProduct: configured,
          }
        : entry))
      return null
    } catch (error) {
      return error instanceof Error ? error.message : 'Complétez la fiche produit avant de la rendre disponible.'
    }
  }

  const setCatalogueDraftPrice = (product: Product, sellingPrice: number): DraftPriceResult => {
    if (!product.tenantCatalogueProduct || product.catalogueStatus !== 'draft') {
      return { error: 'Cette fiche n’a pas de référence de catalogue à mettre à jour.' }
    }
    try {
      const { product: priced, event } = setTenantCatalogueSellingPrice(product.tenantCatalogueProduct, sellingPrice)
      const nextProduct: Product = { ...product, price: priced.sellingPrice ?? product.price, tenantCatalogueProduct: priced }
      setTenantCatalogueProducts((previous) => previous.map((entry) => entry.id === priced.id ? priced : entry))
      setTenantCatalogueEvents((previous) => [...previous, event])
      setProducts((previous) => previous.map((entry) => entry.id === product.id ? nextProduct : entry))
      return { product: nextProduct }
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Le prix de vente est invalide.' }
    }
  }

  const deductCatalogueStockForSale = (items: CartItem[]): string | null => {
    const quantities = new Map<string, number>()
    for (const item of items) quantities.set(item.product.id, (quantities.get(item.product.id) ?? 0) + item.qty)
    try {
      const nextEvents: TenantCatalogueEvent[] = []
      const nextTenantProducts = tenantCatalogueProducts.map((entry) => {
        const quantity = quantities.get(entry.id)
        if (!quantity) return entry
        const { product: updated, event } = deductTenantCatalogueStock(entry, quantity)
        nextEvents.push(event)
        return updated
      })
      setTenantCatalogueProducts(nextTenantProducts)
      if (nextEvents.length) setTenantCatalogueEvents((previous) => [...previous, ...nextEvents])
      setProducts((previous) => previous.map((product) => {
        const quantity = quantities.get(product.id)
        return quantity ? { ...product, stock: Math.max(0, product.stock - quantity) } : product
      }))
      return null
    } catch (error) {
      return error instanceof Error ? error.message : 'Le stock disponible ne permet pas cette vente.'
    }
  }

  const updateShopHours = (shopId: string, openTime: string, closeTime: string, days: string) => {
    setShops((prev) =>
      prev.map((s) => (s.id === shopId ? { ...s, hours: { openTime, closeTime, days } } : s))
    )
  }

  const selectedShop = shops.find((s) => s.id === selectedShopId)

  // Cart & UI state
  const [carts, setCarts] = useState<Cart[]>([
    { id: 'cart-1', name: 'Panier 1', items: [] },
  ])
  const [activeCartId, setActiveCartId] = useState<string>('cart-1')
  const [cartOpen, setCartOpen] = useState(false)
  const [pendingCartsModalOpen, setPendingCartsModalOpen] = useState(false)

  // Mandatory Movement Reason & Express Staged Stock state
  const [stagedStockChanges, setStagedStockChanges] = useState<Record<string, number>>({})
  const [stockMode, setStockMode] = useState<'express' | 'assiste'>('express')
  const [movementReasonModalOpen, setMovementReasonModalOpen] = useState(false)
  const [selectedMovementReason, setSelectedMovementReason] = useState<string>('Entrée Livraison')
  const [pendingMovementReasonSource, setPendingMovementReasonSource] = useState<'express' | 'assiste'>('express')
  const [initialDetailStock, setInitialDetailStock] = useState<number>(0)
  const [selectedProductForDetail, setSelectedProductForDetail] = useState<Product | null>(null)
  const [_movements, setMovements] = useState<any[]>([])
  const [notificationsOpen, setNotificationsOpen] = useState(false)

  const activeCart = carts.find((c) => c.id === activeCartId) || carts[0] || { id: 'cart-1', name: 'Panier 1', items: [] }
  const cart = activeCart.items
  // Le catalogue interne accepte les brouillons à stock inconnu; le catalogue client ne publie que les fiches actives en stock.
  const internalSaleProducts = products.filter((product) => product.catalogueStatus !== 'archived' && (product.tenantCatalogueProduct?.initialStock === null || product.stock > 0))
  const publicCatalogueProducts = products.filter((product) => product.catalogueStatus !== 'draft' && product.catalogueStatus !== 'archived' && product.stock > 0)
  const stockAlertCount = products.filter((product) => product.alert).length

  const navItems: { id: Tab; label: string; icon: React.FC<{ size?: number; color?: string; strokeWidth?: number; className?: string }> }[] = [
    { id: 'accueil', label: 'Accueil', icon: Home },
    { id: 'vente', label: 'Vente', icon: ShoppingCart },
    { id: 'stock', label: 'Stock', icon: Package },
    { id: 'assistant', label: 'Assistant', icon: Bot },
  ]
  const workspace = WORKSPACE_CONFIG[activeWorkspaceRole]
  const workspaceNavItems = commercePolicy.workspaceMode === 'roles_cumules'
    ? navItems
    : navItems.filter((item) => workspace.tabs.includes(item.id))
  const pendingCustomerOrders = clientPwaOrders.filter((order) => order.fulfillmentStatus === 'nouvelle' || order.fulfillmentStatus === 'a_envoyer').length
  const selectWorkspace = (role: WorkspaceRole) => {
    const nextWorkspace = WORKSPACE_CONFIG[role]
    setActiveWorkspaceRole(role)
    if (!nextWorkspace.tabs.includes(tab)) changeTab(nextWorkspace.tabs[0])
    setWorkspaceModalOpen(false)
    showToast(`Espace ${nextWorkspace.label} activé — démonstration locale.`)
  }
  const updateCustomerOrderStatus = (id: string, status: CustomerOrderStatus) => {
    const labels: Record<CustomerOrderStatus, string> = {
      a_envoyer: 'À envoyer — local', nouvelle: 'Nouvelle', acceptee: 'Acceptée', en_preparation: 'En préparation', prete: 'Prête', remise: 'Remise au client', terminee: 'Terminée', refusee: 'Refusée',
    }
    setClientPwaOrders((orders) => orders.map((order) => order.id === id ? { ...order, fulfillmentStatus: status, status: labels[status] } : order))
  }
  const nextCustomerOrderStatus = (status: CustomerOrderStatus): CustomerOrderStatus | null => ({
    a_envoyer: 'nouvelle', nouvelle: 'acceptee', acceptee: 'en_preparation', en_preparation: 'prete', prete: 'remise', remise: 'terminee', terminee: null, refusee: null,
  }[status])
  const customerOrderActionLabel = (status: CustomerOrderStatus) => ({
    a_envoyer: 'Marquer reçue', nouvelle: commercePolicy.stockReservationMoment === 'acceptation' ? 'Accepter & réserver' : 'Accepter', acceptee: 'Préparer', en_preparation: 'Marquer prête', prete: 'Remettre', remise: 'Terminer', terminee: '', refusee: '',
  }[status])

  return (
    <div
      className="lk-app-canvas flex items-center justify-center min-h-screen"
    >
      {/* Phone frame */}
      <div
        className="lk-app-shell relative flex flex-col overflow-hidden shadow-2xl"
      >
        <nav className="lk-desktop-nav" aria-label="Navigation principale">
          <div className="lk-desktop-brand">Lynkstor</div>
          {workspaceNavItems.map(({ id, label, icon: Icon }) => (
            <Button key={id} onClick={() => changeTab(id)} aria-current={tab === id ? 'page' : undefined}>
              <Icon size={20} color="currentColor" /><span>{label}</span>
            </Button>
          ))}
          <div className="mt-auto text-xs px-3 py-4" style={{ color: 'var(--lk-text-secondary)' }}>
            {shopName}<br />{shopCity}
          </div>
        </nav>
        {/* Status bar */}
        <div
          className="lk-status-bar flex items-center justify-between px-6 py-2 flex-shrink-0"
          style={{ paddingTop: '10px' }}
        >
          <span className="text-xs font-semibold text-gray-800">9:41</span>
          <div className="flex items-center gap-1.5">
            <Wifi size={13} color="#1D2939" />
            <div className="flex gap-0.5 items-end">
              {[3, 5, 7, 9].map((h) => (
                <div key={h} className="w-1 rounded-sm bg-gray-800" style={{ height: h }} />
              ))}
            </div>
            <div className="flex items-center gap-0.5">
              <div className="w-5 h-2.5 border border-gray-800 rounded-sm p-0.5 flex items-center">
                <div className="bg-gray-800 rounded-[1px] h-full" style={{ width: '80%' }} />
              </div>
            </div>
          </div>
        </div>

        <LynkstorHeader
          title={tab === 'accueil' ? 'Bonjour, commerçant' : tab === 'assistant' ? 'Assistant IA' : tab === 'stock' ? 'Stock' : 'Vente'}
          subtitle={tab === 'accueil' ? 'Voici un aperçu de votre activité' : tab === 'assistant' ? 'Votre assistant de gestion' : tab === 'stock' ? 'Gestion des articles et inventaire' : 'Caisse · Vente assistée'}
          avatar={<ShopAvatar shop={{ id: 'active-shop', name: shopName, city: shopCity, image: null }} size={44} />}
          cartCount={cart.reduce((sum, item) => sum + item.qty, 0)}
          notificationCount={stockAlertCount}
          qrClientCount={clientPwaOrders.length}
          onCart={() => { changeTab('vente'); setCartOpen(true) }}
          onNotification={() => setNotificationsOpen(!notificationsOpen)}
          onMenu={() => setMenuModalOpen(!menuModalOpen)}
        >
         
        </LynkstorHeader>

        {/* Legacy header retained temporarily while its controls are migrated into LynkstorHeader. */}
        {/* ── APP HEADER BRAND (Adaptatif Intelligent par écran selon Maquettes PNG) ── */}
        <div
          className={`lk-legacy-header lk-app-header flex items-center justify-between gap-2 px-3 py-2 border-b flex-shrink-0 ${(tab === 'stock' || tab === 'assistant') ? 'flex-wrap' : ''}`}
        >
          {/* HEADER BRAND LEFT SIDE */}
          {tab === 'accueil' ? (
            <div className="min-w-0"><ShopIdentity shop={{ id: 'active-shop', name: shopName, city: shopCity, image: null }} size={44} /></div>
          ) : (
            <div className="text-left min-w-0"><h1 className="text-base font-bold leading-tight">{tab === 'assistant' ? 'Assistant' : tab === 'stock' ? 'Stock' : 'Vente'}</h1><p className="text-xs truncate" style={{ color: 'var(--lk-text-secondary)' }}>{shopName}</p></div>
          )}

          {/* HEADER BRAND RIGHT SIDE ACTIONS */}
          <div className="flex items-center gap-1.5 justify-between">
            {tab === 'accueil' && (
              <div className="order-3 flex w-full items-center justify-between gap-2  " >
                <Button
                  onClick={() => showToast("Recherche globale...")}
                  className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-600 hover:bg-gray-200 transition-colors"
                  title="Recherche globale"
                >
                  <Search size={16} color="#475467" />
                </Button>

                <Button
                onClick={() => setMenuModalOpen(!menuModalOpen)}
                className="w-8 h-8 rounded-xl bg-blue-600 flex items-center justify-center text-white transition-all active:scale-95 shadow-sm"
                title="Menu & Administration"
                 >
                  <Menu size={16} color="white" />
                </Button>
              </div>
                           
            )}

              
            {/* Notification button */}
            <Button
              onClick={() => setNotificationsOpen(!notificationsOpen)}
              className="relative w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-600 hover:bg-gray-200 transition-colors"
              title="Notifications"
            >
              <Bell size={16} color="#475467" />
              <span className="absolute top-1 right-1 w-2 h-2 rounded-full bg-red-500 ring-2 ring-white" />
            </Button>

           

            {tab === 'stock' && (
              <div className="order-3 flex w-full items-center justify-between gap-2  " >
                <p className="min-w-0 text-[11px] font-medium truncate" style={{ color: 'var(--lk-text-secondary)' }}>
                  {products.length} articles | {stockAlertCount} à surveiller
                </p>
                <div className="inline-flex shrink-0 rounded-xl border border-gray-200 bg-gray-100 p-0.5" role="tablist" aria-label="Affichage du stock">
                  <Button
                    role="tab"
                    aria-label="Vue catalogue"
                    aria-selected={stockMode === 'express'}
                    onClick={() => setStockMode('express')}
                    className={`flex h-8 items-center gap-1 rounded-lg px-2 text-[11px] font-bold ${stockMode === 'express' ? 'bg-white text-blue-600 shadow-sm' : 'text-gray-500'}`}
                  >
                    <Package size={13} /> 
                  </Button>
                  <Button
                    role="tab"
                    aria-label="Analyse et alertes"
                    aria-selected={stockMode === 'assiste'}
                    onClick={() => setStockMode('assiste')}
                    className={`flex h-8 items-center gap-1 rounded-lg px-2 text-[11px] font-bold ${stockMode === 'assiste' ? 'bg-white text-blue-600 shadow-sm' : 'text-gray-500'}`}
                  >
                    <BarChart3 size={13} /> 
                  </Button>
                </div>
                {/* Menu Button */}
            <Button
              onClick={() => setMenuModalOpen(!menuModalOpen)}
              className="w-8 h-8 rounded-xl bg-blue-600 flex items-center justify-center text-white transition-all active:scale-95 shadow-sm"
              title="Menu & Administration"
            >
              <Menu size={16} color="white" />
            </Button>
              </div>
            )}

             {tab === 'assistant' && (
            <div className="order-3 flex w-full items-center gap-2  ">
              <div
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
                style={{ background: 'linear-gradient(135deg, #0050FF, #7B2FFF)' }}
                aria-hidden="true"
              >
                <Bot size={16} color="white" />
              </div>
              <span className="shrink-0 rounded-full border border-blue-100 bg-blue-50 px-2 py-1 text-[10px] font-bold text-blue-700">Simulation</span>
              <p className="min-w-0 truncate text-[11px] font-medium" style={{ color: 'var(--lk-text-secondary)' }}>À vérifier</p>

              {/* Menu Button */}
            <Button
              onClick={() => setMenuModalOpen(!menuModalOpen)}
              className="w-8 h-8 rounded-xl bg-blue-600 flex items-center justify-center text-white transition-all active:scale-95 shadow-sm"
              title="Menu & Administration"
            >
              <Menu size={16} color="white" />
            </Button>
            

            </div>
          )}

           

          </div>
         
        </div>


        {/* ── MENU DROPDOWN MODAL V2 ── */}
        {menuModalOpen && (
          <Dialog
            className="absolute inset-0 z-50 flex items-start justify-end pt-14 px-4 bg-slate-950/40 backdrop-blur-sm animate-in fade-in duration-200"
            onClick={() => setMenuModalOpen(false)} label="Menu et administration" onDismiss={() => setMenuModalOpen(false)}
          >
            <div
              className="w-80 bg-white/95 backdrop-blur-xl rounded-3xl shadow-2xl p-3 border border-slate-200/80 overflow-hidden max-h-[85vh] flex flex-col animate-in zoom-in-95 duration-200 font-sans"
              onClick={(e) => e.stopPropagation()}
            >
              {/* Merchant Profile Header Card */}
              <div className="p-3 bg-gradient-to-br from-slate-900 to-indigo-950 text-white rounded-2xl space-y-2 mb-2 shadow-md relative overflow-hidden flex-shrink-0">
                <div className="absolute top-0 right-0 w-24 h-24 bg-indigo-500/10 rounded-full blur-xl pointer-events-none" />
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <div className="w-10 h-10 rounded-xl bg-gradient-to-r from-indigo-500 to-purple-500 text-white font-extrabold text-sm flex items-center justify-center flex-shrink-0 shadow-xs border border-white/20">
                      AM
                    </div>
                    <div className="min-w-0">
                      <p className="text-xs font-extrabold text-white leading-tight truncate">Amadou</p>
                      <p className="text-[10px] text-indigo-200 font-medium truncate">{shopName}</p>
                    </div>
                  </div>
                  <Button
                    onClick={() => setMenuModalOpen(false)}
                    className="w-7 h-7 rounded-lg bg-white/10 text-white hover:bg-white/20 flex items-center justify-center transition-colors cursor-pointer" aria-label="Fermer"
                  >
                    <X size={14} />
                  </Button>
                </div>

                <div className="flex items-center gap-1.5 pt-1 border-t border-white/10 text-[10px]">
                  <span className="px-2 py-0.5 rounded-full bg-indigo-500/30 text-indigo-200 font-extrabold border border-indigo-400/30">
                    💎 PRO BUSINESS
                  </span>
                  <span className="px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 font-extrabold border border-emerald-400/30 flex items-center gap-1">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                    Cloud Synchro
                  </span>
                </div>
              </div>

              {/* Scrollable Categorized List */}
              <div className="flex-1 overflow-y-auto space-y-3 pr-1 text-slate-800">
                {/* 1. PILOTAGE & FINANCES */}
                <div className="space-y-1">
                  <p className="text-[9px] font-extrabold text-slate-400 uppercase tracking-wider px-2">
                    📁 Pilotage & Finances
                  </p>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setReportingModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-blue-50/80 active:bg-blue-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <PieChart size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-extrabold text-slate-900">Rapports & Marges</span>
                        <span className="text-[9px] font-extrabold px-1.5 py-0.5 rounded-full bg-blue-100 text-blue-700">Analytics</span>
                      </div>
                      <p className="text-[10px] text-slate-400 truncate">Ventes, marges & export PDF</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setCashClosureModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-emerald-50/80 active:bg-emerald-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Lock size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Clôture de Caisse (Z)</span>
                      <p className="text-[10px] text-slate-400 truncate">Comptage solde & écarts</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setExpenseManagementModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-rose-50/80 active:bg-rose-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-rose-100 text-rose-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <TrendingDown size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-extrabold text-slate-900">Dépenses & OPEX</span>
                        <span className="text-[9px] font-extrabold px-1.5 py-0.5 rounded-full bg-rose-100 text-rose-700">Nouveau</span>
                      </div>
                      <p className="text-[10px] text-slate-400 truncate">Saisie sorties & bénéfice net</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setCreditLedgerModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-amber-50/80 active:bg-amber-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-amber-100 text-amber-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <UserPlus size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Carnet de Dette</span>
                      <p className="text-[10px] text-slate-400 truncate">Créances & relances WhatsApp</p>
                    </div>
                  </Button>
                </div>

                {/* 2. VENTES & CLIENTÈLE */}
                <div className="space-y-1 pt-1 border-t border-slate-100">
                  <p className="text-[9px] font-extrabold text-slate-400 uppercase tracking-wider px-2">
                    ⚡ Ventes & Clientèle
                  </p>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setLoyaltyPromotionsModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-purple-50/80 active:bg-purple-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-purple-600 text-white flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Gift size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Fidélité & Coupons</span>
                      <p className="text-[10px] text-slate-400 truncate">Points, réductions & marketing</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setSupplierOrderModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-blue-50/80 active:bg-blue-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Package size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Commandes Fournisseurs</span>
                      <p className="text-[10px] text-slate-400 truncate">Réappro & WhatsApp Direct</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setClientPwaModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-indigo-50/80 active:bg-indigo-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-indigo-100 text-indigo-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <QrCode size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Aperçu PWA Client</span>
                      <p className="text-[10px] text-slate-400 truncate">Tester Mobile Money Push USSD</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setCustomerOrdersOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-emerald-50/80 active:bg-emerald-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <ClipboardList size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-xs font-extrabold text-slate-900">Commandes clients</span>
                        {pendingCustomerOrders > 0 && <span className="text-[9px] font-extrabold px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-700">{pendingCustomerOrders} nouvelle{pendingCustomerOrders > 1 ? 's' : ''}</span>}
                      </div>
                      <p className="text-[10px] text-slate-400 truncate">Précommandes PWA à traiter</p>
                    </div>
                  </Button>
                </div>

                {/* 3. CONFIGURATION & ÉCOSYSTÈME */}
                <div className="space-y-1 pt-1 border-t border-slate-100">
                  <p className="text-[9px] font-extrabold text-slate-400 uppercase tracking-wider px-2">
                    ⚙️ Configuration & Écosystème
                  </p>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setWorkspaceModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-amber-50/80 active:bg-amber-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-amber-100 text-amber-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Users size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2"><span className="text-xs font-extrabold text-slate-900">Espace de travail</span><span className="text-[9px] font-extrabold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">{workspace.label}</span></div>
                      <p className="text-[10px] text-slate-400 truncate">Changer de rôle et de priorités</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setActiveSettingsSection('index')
                      setSettingsModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-indigo-50/80 active:bg-indigo-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-indigo-600 text-white flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Sliders size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-extrabold text-slate-900">Paramètres</span>
                        <span className="text-[9px] font-extrabold px-1.5 py-0.5 rounded-full bg-indigo-100 text-indigo-700">7 modules</span>
                      </div>
                      <p className="text-[10px] text-slate-400 truncate">Entreprise, POS & synchro</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setSelectedShopId(null)
                      setOwnerSpaceOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-blue-50/80 active:bg-blue-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Store size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-extrabold text-slate-900">Multi-boutiques</span>
                        <span className="text-[9px] font-extrabold px-1.5 py-0.5 rounded-full bg-blue-100 text-blue-700">{shops.length} sites</span>
                      </div>
                      <p className="text-[10px] text-slate-400 truncate">Espace propriétaire consolidé</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setSubscriptionPlansModalOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-purple-50/80 active:bg-purple-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <Award size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Forfaits & Tarifs</span>
                      <p className="text-[10px] text-slate-400 truncate">Starter, Essential, Pro, Business</p>
                    </div>
                  </Button>

                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      setEventLogInspectorOpen(true)
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-emerald-50/80 active:bg-emerald-100/80 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <FileText size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-extrabold text-slate-900">Journal d'Événements</span>
                      <p className="text-[10px] text-slate-400 truncate">Event sourcing local & audit</p>
                    </div>
                  </Button>
                </div>

                {/* 4. SYSTÈME */}
                <div className="space-y-1 pt-1 border-t border-slate-100">
                  <Button
                    onClick={() => {
                      setMenuModalOpen(false)
                      onResetOnboarding()
                    }}
                    className="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-slate-100 active:bg-slate-200 text-left transition-all group cursor-pointer"
                  >
                    <div className="w-8 h-8 rounded-xl bg-slate-100 text-slate-600 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform shadow-2xs">
                      <RotateCcw size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-xs font-bold text-slate-800">Re-tester l'onboarding</span>
                      <p className="text-[10px] text-slate-400 truncate">Changer de boutique active</p>
                    </div>
                  </Button>
                </div>
              </div>
            </div>
          </Dialog>
        )}

        {workspaceModalOpen && (
          <Dialog className="absolute inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/40 backdrop-blur-sm" label="Choisir un espace de travail" onDismiss={() => setWorkspaceModalOpen(false)}>
            <div className="w-full max-w-md max-h-[88vh] overflow-y-auto rounded-3xl bg-white p-5 shadow-2xl space-y-4">
              <div className="flex items-start justify-between gap-3">
                <div><h2 className="text-base font-bold text-gray-900">Espace de travail</h2><p className="mt-1 text-xs text-gray-500">Les priorités changent selon le rôle. Les droits réels doivent rester contrôlés par le service.</p></div>
                <Button onClick={() => setWorkspaceModalOpen(false)} className="p-2 rounded-xl bg-gray-100 text-gray-600" aria-label="Fermer"><X size={18} /></Button>
              </div>
              <div className="space-y-2" role="radiogroup" aria-label="Rôle actif">
                {(Object.keys(WORKSPACE_CONFIG) as WorkspaceRole[]).map((role) => {
                  const item = WORKSPACE_CONFIG[role]
                  const selected = role === activeWorkspaceRole
                  return <Button key={role} role="radio" aria-checked={selected} onClick={() => selectWorkspace(role)} className={`w-full min-h-16 rounded-2xl border p-3 text-left transition-colors ${selected ? 'border-blue-600 bg-blue-50' : 'border-gray-200 hover:bg-gray-50'}`}>
                    <span className="flex items-start justify-between gap-3"><span><strong className="block text-sm text-gray-900">{item.label}</strong><span className="mt-0.5 block text-xs text-gray-500">{item.description}</span></span>{selected && <CheckCircle size={19} className="shrink-0 text-blue-600" />}</span>
                  </Button>
                })}
              </div>
              <p className="rounded-xl border border-amber-100 bg-amber-50 p-3 text-[11px] leading-relaxed text-amber-900"><strong>Mode démonstration.</strong> Cet écran adapte le prototype ; il ne remplace pas l’autorisation serveur par tenant et boutique.</p>
            </div>
          </Dialog>
        )}

        {customerOrdersOpen && (
          <Dialog className="absolute inset-0 z-50 flex flex-col bg-slate-50" label="Commandes clients" onDismiss={() => setCustomerOrdersOpen(false)}>
            <div className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-100 bg-white px-4 py-4">
              <div><h2 className="text-base font-bold text-gray-900">Commandes clients</h2><p className="text-[11px] font-medium text-emerald-700">{workspace.label} · {pendingCustomerOrders} à traiter</p></div>
              <Button onClick={() => setCustomerOrdersOpen(false)} className="p-2 rounded-xl bg-gray-100 text-gray-600" aria-label="Fermer"><X size={18} /></Button>
            </div>
            <div className="flex-1 space-y-3 overflow-y-auto p-4">
              <div className="rounded-2xl border border-sky-100 bg-sky-50 p-3 text-xs leading-relaxed text-sky-900"><strong>File locale de démonstration.</strong> Une commande est distincte d’une vente. Le stock et le paiement ne sont pas confirmés par cette interface seule.</div>
              {clientPwaOrders.filter((order) => order.shopName === shopName).map((order) => {
                const status = order.fulfillmentStatus ?? 'terminee'
                const next = nextCustomerOrderStatus(status)
                return <article key={order.id} className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm space-y-3">
                  <div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="text-sm font-bold text-gray-900">{order.id}</p><p className="truncate text-xs text-gray-500" title={order.customerName}>{order.customerName || 'Client PWA non identifié'} · {order.date}</p></div><span className="shrink-0 rounded-full bg-emerald-50 px-2 py-1 text-[10px] font-bold text-emerald-700">{order.status}</span></div>
                  <div className="rounded-xl bg-gray-50 p-2.5 text-xs text-gray-700">{order.items.map((item) => `${item.qty} × ${item.name}`).join(' · ')}<strong className="mt-1 block text-gray-900">{order.total.toLocaleString('fr-FR')} FCFA · {order.payMethod}</strong></div>
                  {next && <div className="flex gap-2"><Button onClick={() => { updateCustomerOrderStatus(order.id, next); showToast(`Commande ${order.id} : ${customerOrderActionLabel(status)}.`) }} className="flex-1 rounded-xl bg-emerald-600 px-3 py-2.5 text-xs font-bold text-white">{customerOrderActionLabel(status)}</Button>{(status === 'nouvelle' || status === 'a_envoyer') && <Button onClick={() => updateCustomerOrderStatus(order.id, 'refusee')} className="rounded-xl border border-rose-200 bg-rose-50 px-3 py-2.5 text-xs font-bold text-rose-700">Refuser</Button>}</div>}
                </article>
              })}
            </div>
          </Dialog>
        )}

        {/* ── MODAL PANIERS EN ATTENTES (Maquette Vante - sélection Panier en attenteFichier 6.png) ── */}
        {pendingCartsModalOpen && (
          <Dialog
            className="absolute inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs animate-backdrop"
            onClick={() => setPendingCartsModalOpen(false)} label="Paniers en attente" onDismiss={() => setPendingCartsModalOpen(false)}
          >
            <div
              className="w-full max-w-xs bg-white rounded-2xl shadow-2xl p-3 border border-gray-100 overflow-hidden perspective-1000 animate-card-flip"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between pb-2 border-b border-gray-100">
                <h3 className="text-xs font-bold text-gray-900">3 Paniers en attentes</h3>
                <Button
                  onClick={() => setPendingCartsModalOpen(false)}
                  className="w-6 h-6 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 hover:bg-gray-200" aria-label="Fermer"
                >
                  <X size={14} />
                </Button>
              </div>

              <div className="py-2 space-y-2">
                {/* Option 1: Ajouter second panier */}
                <Button
                  onClick={() => {
                    const newId = `cart-${Date.now()}`
                    const newCartName = `Panier ${carts.length + 1}`
                    setCarts((prev) => [...prev, { id: newId, name: newCartName, items: [] }])
                    setActiveCartId(newId)
                    setPendingCartsModalOpen(false)
                    showToast(`${newCartName} créé !`)
                  }}
                  className="w-full flex items-center gap-2.5 p-2 rounded-xl bg-blue-50/80 hover:bg-blue-100 text-left transition-colors border border-blue-100"
                >
                  <div className="w-7 h-7 rounded-full bg-blue-200 text-blue-700 flex items-center justify-center font-bold text-xs">
                    +1
                  </div>
                  <span className="text-xs font-semibold text-blue-900">Ajouter second Panier</span>
                </Button>

                {/* Cart 1: Marie M. */}
                <Button
                  onClick={() => {
                    setPendingCartsModalOpen(false)
                    showToast("Panier Marie M. sélectionné")
                  }}
                  className="flex items-center justify-between p-2 rounded-xl hover:bg-gray-50 cursor-pointer border border-gray-100 transition-colors"
                >
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-full bg-sky-500 text-white flex items-center justify-center text-xs font-bold shadow-2xs">
                      🛒2
                    </div>
                    <div>
                      <p className="text-xs font-bold text-gray-900">Marie M.</p>
                    </div>
                  </div>
                  <span className="text-[9px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                    Client Boutique
                  </span>
                </Button>

                {/* Cart 2: Jean Pierre */}
                <Button
                  onClick={() => {
                    setPendingCartsModalOpen(false)
                    showToast("Panier Jean Pierre sélectionné")
                  }}
                  className="flex items-center justify-between p-2 rounded-xl hover:bg-gray-50 cursor-pointer border border-gray-100 transition-colors"
                >
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-full bg-amber-500 text-white flex items-center justify-center text-xs font-bold shadow-2xs">
                      🛒8
                    </div>
                    <div>
                      <p className="text-xs font-bold text-gray-900">Jean Pierre</p>
                      <p className="text-[8px] text-gray-400 font-medium">Tel: 69611122233</p>
                    </div>
                  </div>
                  <span className="text-[9px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
                    PWA Client
                  </span>
                </Button>

                {/* Cart 3: Panier 2 */}
                <Button
                  onClick={() => {
                    setPendingCartsModalOpen(false)
                    showToast("Panier 2 sélectionné")
                  }}
                  className="flex items-center justify-between p-2 rounded-xl bg-emerald-50/60 hover:bg-emerald-100/60 cursor-pointer border border-emerald-200 transition-colors"
                >
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-full bg-emerald-600 text-white flex items-center justify-center text-xs font-bold shadow-2xs">
                      🛒9+
                    </div>
                    <div>
                      <p className="text-xs font-bold text-gray-900">Panier 2</p>
                      <p className="text-[8px] text-gray-400 font-medium">Client Anonyme</p>
                    </div>
                  </div>
                  <span className="text-[9px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                    Client Boutique
                  </span>
                </Button>
              </div>
            </div>
          </Dialog>
        )}

        {/* ── MODAL MOTIF DE MOUVEMENT DE STOCK OBLIGATOIRE ── */}
        {movementReasonModalOpen && (
          <Dialog
            className="absolute inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-backdrop"
            onClick={() => {
              if (confirm("Annuler l'enregistrement du motif et annuler les modifications ?")) {
                setStagedStockChanges({})
                setMovementReasonModalOpen(false)
              }
            }} label="Motif du mouvement" onDismiss={() => setMovementReasonModalOpen(false)}
          >
            <div
              className="w-full max-w-xs bg-white rounded-3xl p-4 space-y-3 shadow-2xl perspective-1000 animate-card-flip"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between pb-2 border-b border-gray-100">
                <div className="flex items-center gap-2">
                  <div className="w-8 h-8 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center font-bold text-sm">
                    📋
                  </div>
                  <div>
                    <h3 className="font-bold text-gray-900 text-xs">Motif de Mouvement Obligatoire</h3>
                    <p className="text-[9px] text-gray-400 font-medium">Sélectionner la raison pour le registre stock</p>
                  </div>
                </div>
                <Button
                  onClick={() => {
                    if (confirm("Annuler l'enregistrement du motif et annuler les modifications ?")) {
                      setStagedStockChanges({})
                      setMovementReasonModalOpen(false)
                    }
                  }}
                  className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer"
                >
                  <X size={16} />
                </Button>
              </div>

              {/* List of 7 mandatory movement reasons */}
              <div className="space-y-1.5 max-h-64 overflow-y-auto pr-0.5">
                {[
                  { key: 'Entrée Livraison', label: '📥 Entrée Livraison', desc: 'Réception fournisseur ou bon d’achat' },
                  { key: 'Sortie / Transfert', label: '📤 Sortie / Transfert', desc: 'Transfert vers autre boutique ou dépôt' },
                  { key: 'Retour Client', label: '↩️ Retour Client', desc: 'Produit ramené par un client' },
                  { key: 'Retour Fournisseur', label: '🚚 Retour Fournisseur', desc: 'Renvoi de marchandises défectueuses' },
                  { key: 'Casse / Perte / Vol', label: '💔 Casse / Perte / Vol', desc: 'Période de démarque inconnue ou avarie' },
                  { key: 'Consommation Interne', label: '☕ Consommation Interne', desc: 'Utilisé par le personnel ou la boutique' },
                  { key: 'Ajustement Inventaire', label: '⚖️ Ajustement Inventaire', desc: 'Correction suite au comptage physique' },
                ].map((item) => {
                  const isSelected = selectedMovementReason === item.key
                  return (
                    <Button
                      key={item.key}
                      onClick={() => setSelectedMovementReason(item.key)}
                      className={`p-2 rounded-xl cursor-pointer border transition-all flex items-center justify-between ${isSelected
                        ? 'bg-purple-50 border-purple-500 text-purple-900 font-bold shadow-2xs'
                        : 'bg-gray-50 border-gray-100 text-gray-700 hover:bg-gray-100'
                        }`}
                    >
                      <div>
                        <p className="text-xs font-bold">{item.label}</p>
                        <p className="text-[8px] text-gray-400 font-medium">{item.desc}</p>
                      </div>
                      {isSelected && <CheckCircle size={15} className="text-purple-600 flex-shrink-0" />}
                    </Button>
                  )
                })}
              </div>

              <div className="flex gap-2 pt-2 border-t border-gray-100">
                <Button
                  onClick={() => {
                    setStagedStockChanges({})
                    setMovementReasonModalOpen(false)
                  }}
                  className="flex-1 py-2.5 rounded-xl text-gray-600 font-bold text-xs bg-gray-100 hover:bg-gray-200 transition-colors"
                >
                  Annuler
                </Button>
                <Button
                  onClick={() => {
                    if (pendingMovementReasonSource === 'express') {
                      setProducts((prev) =>
                        prev.map((p) => {
                          if (stagedStockChanges[p.id] !== undefined) {
                            const delta = stagedStockChanges[p.id] - p.stock
                            if (delta !== 0) {
                              setMovements((mPrev) => [
                                {
                                  id: `mov-${Date.now()}-${p.id}`,
                                  date: new Date().toLocaleDateString('fr-FR'),
                                  type: delta > 0 ? 'purchase' : 'adjustment',
                                  qty: Math.abs(delta),
                                  description: `${selectedMovementReason} (${delta > 0 ? '+' : ''}${delta} u. sur ${p.name})`,
                                },
                                ...mPrev,
                              ])
                            }
                            return { ...p, stock: stagedStockChanges[p.id] }
                          }
                          return p
                        })
                      )
                      setStagedStockChanges({})
                      showToast?.(`Stock mis à jour avec motif : ${selectedMovementReason}`)
                    } else if (pendingMovementReasonSource === 'assiste' && selectedProductForDetail) {
                      const delta = selectedProductForDetail.stock - initialDetailStock
                      if (delta !== 0) {
                        setMovements((mPrev) => [
                          {
                            id: `mov-${Date.now()}`,
                            date: new Date().toLocaleDateString('fr-FR'),
                            type: delta > 0 ? 'purchase' : 'adjustment',
                            qty: Math.abs(delta),
                            description: `${selectedMovementReason} (${delta > 0 ? '+' : ''}${delta} u. sur ${selectedProductForDetail.name})`,
                          },
                          ...mPrev,
                        ])
                      }
                      setProducts((prev) =>
                        prev.map((p) => (p.id === selectedProductForDetail.id ? selectedProductForDetail : p))
                      )
                      setSelectedProductForDetail(null)
                      showToast?.(`Fiche enregistrée avec motif : ${selectedMovementReason}`)
                    }
                    setMovementReasonModalOpen(false)
                  }}
                  className="flex-1 py-2.5 rounded-xl text-white font-bold text-xs bg-purple-600 hover:bg-purple-700 active:scale-95 transition-all shadow-md"
                >
                  Valider motif
                </Button>
              </div>
            </div>
          </Dialog>
        )}

        {/* ── ESPACE PROPRIÉTAIRE (MULTI-BOUTIQUE) ── */}
        {ownerSpaceOpen && (
          <Dialog className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200" label="Gestion des boutiques" onDismiss={() => setOwnerSpaceOpen(false)}>
            {/* Modal Header */}
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => {
                  if (selectedShopId !== null) {
                    setSelectedShopId(null)
                  } else {
                    setOwnerSpaceOpen(false)
                  }
                }}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">
                  {selectedShopId !== null && selectedShop ? selectedShop.name : 'Mes boutiques'}
                </h2>
                <p className="text-[11px] text-blue-600 font-medium">
                  {selectedShopId !== null && selectedShop ? `${selectedShop.city} · Détail boutique` : 'Vue Propriétaire & Groupe'}
                </p>
              </div>
              <Button
                onClick={() => setOwnerSpaceOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            {/* Content Area */}
            <div className="p-4 space-y-4 flex-1">
              {selectedShopId === null ? (
                /* ── ÉCRAN 1: MES BOUTIQUES ── */
                <>
                  {/* Top 2 KPI Cards */}
                  <div className="grid grid-cols-2 gap-3">
                    <div className="p-3.5 rounded-2xl bg-white border border-gray-100 shadow-sm flex flex-col justify-between">
                      <div className="w-8 h-8 rounded-xl bg-blue-50 flex items-center justify-center mb-2">
                        <BarChart3 size={18} color="#0050FF" />
                      </div>
                      <div>
                        <p className="text-[10px] font-bold text-gray-400 uppercase tracking-wider">CA consolidé — 7j</p>
                        <p className="text-base font-bold text-gray-900 mt-0.5">
                          {shops.reduce((sum, s) => sum + s.revenue7d, 0).toLocaleString('fr-FR')} <span className="text-xs font-normal text-gray-400">FCFA</span>
                        </p>
                      </div>
                    </div>

                    <div className="p-3.5 rounded-2xl bg-white border border-gray-100 shadow-sm flex flex-col justify-between">
                      <div className="w-8 h-8 rounded-xl bg-emerald-50 flex items-center justify-center mb-2">
                        <Store size={18} color="#12B76A" />
                      </div>
                      <div>
                        <p className="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Boutiques actives</p>
                        <p className="text-base font-bold text-gray-900 mt-0.5">{shops.length} <span className="text-xs font-normal text-gray-400">sites</span></p>
                      </div>
                    </div>
                  </div>

                  {/* Explicit Rule Banner */}
                  <div className="p-3.5 bg-blue-50/70 border border-blue-100 rounded-2xl flex items-start gap-2.5 text-xs text-blue-900">
                    <Info size={16} color="#0050FF" className="flex-shrink-0 mt-0.5" />
                    <p className="leading-relaxed">
                      <strong className="font-bold">Chaque boutique reste autonome</strong> — vue consolidée en lecture seule. Aucun partage de stock ni de dette client.
                    </p>
                  </div>

                  {/* List of Stores */}
                  <div className="space-y-2">
                    <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Liste des établissements ({shops.length})</p>
                    <div className="divide-y divide-gray-100 border border-gray-100 rounded-2xl bg-white overflow-hidden shadow-sm">
                      {shops.map((shop) => (
                        <Button
                          key={shop.id}
                          onClick={() => setSelectedShopId(shop.id)}
                          className="min-h-16 w-full p-3.5 flex flex-col items-stretch gap-3 text-left hover:bg-gray-50 cursor-pointer active:bg-blue-50/40 transition-colors sm:flex-row sm:items-center sm:justify-between"
                        >
                          <div className="min-w-0 flex-1 space-y-1">
                            <div className="flex items-center gap-1.5 flex-wrap">
                              <span className="break-words text-sm font-bold text-gray-900">{shop.name}</span>
                              {shop.isCurrentAppShop && (
                                <span className="px-2 py-0.5 rounded-full text-[9px] font-bold bg-blue-100 text-blue-700">
                                  Active dans l'app
                                </span>
                              )}
                            </div>
                            <p className="break-words text-xs text-gray-500">
                              📍 {shop.city} · 🕒 {shop.hours.openTime} - {shop.hours.closeTime} ({shop.hours.days})
                            </p>
                            <p className="text-xs text-gray-400 font-medium">
                              👥 {shop.staff.length} membre{shop.staff.length > 1 ? 's' : ''} du personnel
                            </p>
                          </div>
                          <div className="flex items-center justify-between gap-2 border-t border-gray-100 pt-2 text-right sm:justify-end sm:border-t-0 sm:pt-0 flex-shrink-0">
                            <div>
                              <p className="text-xs font-bold text-gray-900">{shop.revenue7d.toLocaleString('fr-FR')} FCFA</p>
                              <p className="text-[10px] text-gray-400 font-medium">CA 7 jours</p>
                            </div>
                            <ChevronRight size={16} color="#D0D5DD" />
                          </div>
                        </Button>
                      ))}
                    </div>

                    <Button
                      onClick={() => {
                        setNewShopName('')
                        setNewShopCity('')
                        setNewShopSector('Épicerie')
                        setNewShopCategories(SECTORS[0].categories)
                        setCreateShopStep(1)
                        setCreateShopModalOpen(true)
                      }}
                      className="w-full py-3.5 rounded-2xl text-white font-bold text-sm shadow-md flex items-center justify-center gap-2 active:scale-95 transition-transform"
                      style={{ backgroundColor: '#0050FF' }}
                    >
                      <Plus size={18} />
                      <span>Ajouter une boutique</span>
                    </Button>
                  </div>
                </>
              ) : selectedShop ? (
                /* ── ÉCRAN 2: DÉTAIL BOUTIQUE ── */
                <>
                  {/* Horaires d'ouverture */}
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <Clock size={16} color="#0050FF" />
                        <h3 className="font-bold text-gray-900 text-sm">Horaires d'ouverture</h3>
                      </div>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-green-50 text-green-700">
                        {selectedShop.hours.openTime} - {selectedShop.hours.closeTime}
                      </span>
                    </div>

                    <div className="grid grid-cols-2 gap-2">
                      <div>
                        <label className="text-[11px] font-bold text-gray-600">Ouverture</label>
                        <Input
                          type="time"
                          value={selectedShop.hours.openTime}
                          onChange={(e) => updateShopHours(selectedShop.id, e.target.value, selectedShop.hours.closeTime, selectedShop.hours.days)}
                          className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-xs font-semibold outline-none"
                        />
                      </div>
                      <div>
                        <label className="text-[11px] font-bold text-gray-600">Fermeture</label>
                        <Input
                          type="time"
                          value={selectedShop.hours.closeTime}
                          onChange={(e) => updateShopHours(selectedShop.id, selectedShop.hours.openTime, e.target.value, selectedShop.hours.days)}
                          className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-xs font-semibold outline-none"
                        />
                      </div>
                    </div>

                    <div>
                      <label className="text-[11px] font-bold text-gray-600">Jours d'activité</label>
                      <Input
                        type="text"
                        value={selectedShop.hours.days}
                        onChange={(e) => updateShopHours(selectedShop.id, selectedShop.hours.openTime, selectedShop.hours.closeTime, e.target.value)}
                        placeholder="Ex: Lun - Sam"
                        className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-2.5 text-xs font-semibold outline-none"
                      />
                    </div>

                    <p className="text-[10px] text-gray-400 italic">
                      💬 Statut d'affichage uniquement — n'impose aucun blocage sur les ventes.
                    </p>

                    <Button
                      onClick={() => showToast(`Horaires enregistrés pour ${selectedShop.name} !`)}
                      className="w-full py-2.5 rounded-xl bg-blue-50 text-blue-700 font-bold text-xs hover:bg-blue-100 transition-colors"
                    >
                      Enregistrer les horaires
                    </Button>
                  </div>

                  {/* Informations Légales du Groupe / Entreprise */}
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <Building size={16} color="#0050FF" />
                        <h3 className="font-bold text-gray-900 text-sm">Informations légales du Groupe</h3>
                      </div>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700">
                        Entreprise
                      </span>
                    </div>

                    <div className="bg-gray-50 rounded-xl p-3 space-y-1 text-xs">
                      <p className="text-gray-700"><strong className="font-bold text-gray-900">Entreprise :</strong> {enterpriseInfo.companyName}</p>
                      <p className="text-gray-700"><strong className="font-bold text-gray-900">NIU :</strong> {enterpriseInfo.niu || 'Non renseigné'}</p>
                      <p className="text-gray-700"><strong className="font-bold text-gray-900">RCCM :</strong> {enterpriseInfo.rccm || 'Non renseigné'}</p>
                      <p className="text-gray-700"><strong className="font-bold text-gray-900">Siège social :</strong> {enterpriseInfo.headOfficeCity}</p>
                    </div>

                    <Button
                      onClick={() => {
                        setEditEnterpriseCompanyName(enterpriseInfo.companyName)
                        setEditEnterpriseNiu(enterpriseInfo.niu || '')
                        setEditEnterpriseRccm(enterpriseInfo.rccm || '')
                        setEditEnterpriseHeadCity(enterpriseInfo.headOfficeCity)
                        setActiveSettingsSection('enterprise')
                        setSettingsModalOpen(true)
                      }}
                      className="w-full py-2.5 rounded-xl bg-blue-50 text-blue-700 font-bold text-xs hover:bg-blue-100 transition-colors flex items-center justify-center gap-1.5"
                    >
                      <Sliders size={14} />
                      <span>Gérer dans Paramètres de l'entreprise</span>
                    </Button>
                  </div>

                  {/* Personnel affecté */}
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex min-w-0 items-center gap-2">
                        <Users size={16} color="#0050FF" />
                        <h3 className="break-words font-bold text-gray-900 text-sm">Personnel affecté</h3>
                      </div>
                      <span className="shrink-0 whitespace-nowrap text-xs text-gray-400 font-medium">{selectedShop.staff.length} personnes</span>
                    </div>

                    <div className="divide-y divide-gray-100 border border-gray-100 rounded-xl overflow-hidden">
                      {selectedShop.staff.map((st) => (
                        <Button
                          key={st.id}
                          onClick={() => {
                            setEditingStaff({ staff: st, fromShopId: selectedShop.id })
                            setEditStaffRole(st.role)
                            setEditStaffShopId(selectedShop.id)
                          }}
                          className="min-h-14 w-full p-3 flex flex-col items-stretch gap-2 text-left hover:bg-gray-50 cursor-pointer transition-colors sm:flex-row sm:items-center sm:justify-between"
                        >
                          <div className="min-w-0 flex-1">
                            <p className="break-words text-sm font-bold text-gray-900">{st.name}</p>
                            <p className="break-words text-[10px] text-gray-400 mt-0.5">Cliquez pour modifier ou réaffecter</p>
                          </div>
                          <div className="flex items-center justify-between gap-2 sm:justify-end">
                            {st.role === 'caisse' && (
                              <span className="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-50 text-blue-700 border border-blue-100 flex items-center gap-1">
                                <Banknote size={11} /> Caisse
                              </span>
                            )}
                            {st.role === 'stock' && (
                              <span className="px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-50 text-amber-700 border border-amber-100 flex items-center gap-1">
                                <Package size={11} /> Stock
                              </span>
                            )}
                            {st.role === 'supervision' && (
                              <span className="px-2.5 py-1 rounded-full text-[10px] font-bold bg-purple-50 text-purple-700 border border-purple-100 flex items-center gap-1">
                                <Shield size={11} /> Supervision
                              </span>
                            )}
                            <ChevronRight size={14} color="#D0D5DD" />
                          </div>
                        </Button>
                      ))}
                    </div>

                    <Button
                      onClick={() => {
                        setNewStaffName('')
                        setNewStaffRole('caisse')
                        setAddStaffModalOpen(true)
                      }}
                      className="w-full py-3 rounded-2xl bg-blue-50 text-blue-700 border border-blue-200 font-bold text-xs flex items-center justify-center gap-2 active:scale-95 transition-transform"
                    >
                      <Plus size={15} />
                      <span>Ajouter un personnel</span>
                    </Button>
                  </div>
                </>
              ) : null}
            </div>
          </Dialog>
        )}

        {/* ── MODAL: NOUVEAU PERSONNEL ── */}
        {addStaffModalOpen && selectedShop && (
          <div
            className="absolute inset-0 z-50 flex items-center justify-center px-4 bg-black/50 backdrop-blur-xs animate-backdrop"
            onClick={() => setAddStaffModalOpen(false)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl perspective-1000 animate-card-flip max-h-[90vh] overflow-y-auto"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Nouveau personnel</h3>
                  <p className="text-xs text-blue-600 font-medium">Affecté à {selectedShop.name}</p>
                </div>
                <Button onClick={() => setAddStaffModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Nom du personnel</label>
                <Input
                  type="text"
                  value={newStaffName}
                  onChange={(e) => setNewStaffName(e.target.value)}
                  placeholder="Ex: Jean-Baptiste Abena"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                  autoFocus
                />
              </div>

              {/* Sélecteur de rôle (Pattern Cartes d'options) */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-gray-700">Rôle attribué</label>
                <div className="space-y-2">
                  {[
                    { id: 'caisse', title: 'Tenue de caisse', desc: 'Encaissement des ventes, gestion des espèces & Mobile Money', icon: Banknote },
                    { id: 'stock', title: 'Gestion de stock', desc: 'Réception des factures, ajustement des quantités et réassort', icon: Package },
                    { id: 'supervision', title: 'Supervision globale', desc: 'Accès complet, contrôle des prix et rapports de marge', icon: Shield },
                  ].map((r) => {
                    const active = newStaffRole === r.id
                    const IconComp = r.icon
                    return (
                      <Button
                        key={r.id}
                        onClick={() => setNewStaffRole(r.id as any)}
                        className={`p-3 rounded-2xl border-2 transition-all cursor-pointer flex items-center gap-3 ${active ? 'border-[#0050FF] bg-[#EFF4FF] shadow-sm' : 'border-gray-100 bg-white hover:border-gray-200'
                          }`}
                      >
                        <div className={`w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0 ${active ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-600'}`}>
                          <IconComp size={18} />
                        </div>
                        <div className="flex-1">
                          <p className="text-xs font-bold text-gray-900">{r.title}</p>
                          <p className="text-[10px] text-gray-500 leading-tight mt-0.5">{r.desc}</p>
                        </div>
                        {active && <Check size={16} color="#0050FF" />}
                      </Button>
                    )
                  })}
                </div>
              </div>

              <Button
                disabled={!newStaffName.trim()}
                onClick={() => {
                  const newStaff: ShopStaff = {
                    id: `st-${Date.now()}`,
                    name: newStaffName.trim(),
                    role: newStaffRole,
                  }
                  setShops((prev) =>
                    prev.map((s) => (s.id === selectedShop.id ? { ...s, staff: [...s.staff, newStaff] } : s))
                  )
                  showToast(`${newStaffName} ajouté à ${selectedShop.name} !`)
                  setAddStaffModalOpen(false)
                }}
                className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-all disabled:opacity-40 shadow-md"
              >
                Ajouter à cette boutique
              </Button>
            </div>
          </div>
        )}

        {/* ── MODAL: RÉAFFECTATION / ÉDITION PERSONNEL ── */}
        {editingStaff && (
          <div
            className="absolute inset-0 z-50 flex items-center justify-center px-4 bg-black/50 backdrop-blur-xs animate-backdrop"
            onClick={() => setEditingStaff(null)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl perspective-1000 animate-card-flip max-h-[90vh] overflow-y-auto"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Édition & Réaffectation</h3>
                  <p className="text-xs text-blue-600 font-medium">{editingStaff.staff.name}</p>
                </div>
                <Button onClick={() => setEditingStaff(null)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              {/* Sélecteur de rôle */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-gray-700">Rôle du personnel</label>
                <div className="space-y-2">
                  {[
                    { id: 'caisse', title: 'Tenue de caisse', desc: 'Encaissement des ventes, espèces & Mobile Money', icon: Banknote },
                    { id: 'stock', title: 'Gestion de stock', desc: 'Réception des factures, ajustement des quantités', icon: Package },
                    { id: 'supervision', title: 'Supervision globale', desc: 'Accès complet, contrôle des prix et rapports de marge', icon: Shield },
                  ].map((r) => {
                    const active = editStaffRole === r.id
                    const IconComp = r.icon
                    return (
                      <Button
                        key={r.id}
                        onClick={() => setEditStaffRole(r.id as any)}
                        className={`p-3 rounded-2xl border-2 transition-all cursor-pointer flex items-center gap-3 ${active ? 'border-[#0050FF] bg-[#EFF4FF] shadow-sm' : 'border-gray-100 bg-white hover:border-gray-200'
                          }`}
                      >
                        <div className={`w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0 ${active ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-600'}`}>
                          <IconComp size={18} />
                        </div>
                        <div className="flex-1">
                          <p className="text-xs font-bold text-gray-900">{r.title}</p>
                          <p className="text-[10px] text-gray-500 leading-tight mt-0.5">{r.desc}</p>
                        </div>
                        {active && <Check size={16} color="#0050FF" />}
                      </Button>
                    )
                  })}
                </div>
              </div>

              {/* Sélection de la boutique d'affectation */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-gray-700">Boutique d'affectation</label>
                <div className="space-y-2">
                  {shops.map((s) => {
                    const isSelected = editStaffShopId === s.id
                    return (
                      <Button
                        key={s.id}
                        onClick={() => setEditStaffShopId(s.id)}
                        className={`p-3 rounded-2xl border-2 transition-all cursor-pointer flex items-center justify-between ${isSelected ? 'border-[#0050FF] bg-[#EFF4FF]' : 'border-gray-100 bg-white'
                          }`}
                      >
                        <div>
                          <p className="text-xs font-bold text-gray-900">{s.name}</p>
                          <p className="text-[10px] text-gray-500">📍 {s.city}</p>
                        </div>
                        {isSelected && <Check size={16} color="#0050FF" />}
                      </Button>
                    )
                  })}
                </div>
              </div>

              <Button
                onClick={() => {
                  setShops((prev) =>
                    prev.map((s) => {
                      // Retire de l'ancienne boutique si changement de site
                      if (s.id === editingStaff.fromShopId && s.id !== editStaffShopId) {
                        return { ...s, staff: s.staff.filter((st) => st.id !== editingStaff.staff.id) }
                      }
                      // Ajoute ou met à jour dans la nouvelle boutique
                      if (s.id === editStaffShopId) {
                        const exists = s.staff.some((st) => st.id === editingStaff.staff.id)
                        if (exists) {
                          return {
                            ...s,
                            staff: s.staff.map((st) =>
                              st.id === editingStaff.staff.id ? { ...st, role: editStaffRole } : st
                            ),
                          }
                        } else {
                          return {
                            ...s,
                            staff: [...s.staff, { ...editingStaff.staff, role: editStaffRole }],
                          }
                        }
                      }
                      return s
                    })
                  )

                  const targetShop = shops.find((s) => s.id === editStaffShopId)
                  showToast(`${editingStaff.staff.name} réaffecté à ${targetShop?.name || 'la boutique'} !`)
                  setEditingStaff(null)
                }}
                className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-all shadow-md"
              >
                Enregistrer la réaffectation
              </Button>
            </div>
          </div>
        )}

        {/* ── MODAL HUB: PARAMÈTRES ET ADMINISTRATION ── */}
        {settingsModalOpen && (
          <Dialog className="lk-settings-modal absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200" label="Paramètres" onDismiss={() => setSettingsModalOpen(false)}>
            {/* Header */}
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => {
                  if (activeSettingsSection !== 'index') {
                    setActiveSettingsSection('index')
                  } else {
                    setSettingsModalOpen(false)
                  }
                }}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">
                  {activeSettingsSection === 'index' && 'Paramètres'}
                  {activeSettingsSection === 'appearance' && 'Apparence'}
                  {activeSettingsSection === 'catalogue' && 'Catalogue & images'}
                  {activeSettingsSection === 'enterprise' && 'Mon Entreprise'}
                  {activeSettingsSection === 'sector' && "Secteur d'activité"}
                  {activeSettingsSection === 'devices' && 'Appareils connectés'}
                  {activeSettingsSection === 'modules' && 'Modules activés'}
                  {activeSettingsSection === 'sync' && 'Synchronisation locale'}
                  {activeSettingsSection === 'commerce' && 'Règles de commerce'}
                </h2>
                <p className="text-[11px] text-blue-600 font-medium">{enterpriseInfo.companyName}</p>
              </div>
              <Button
                onClick={() => setSettingsModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            {/* Body */}
            <div className="p-4 space-y-4 flex-1">
              {activeSettingsSection === 'index' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  {/* Enterprise Banner Card */}
                  <div
                    className="lk-settings-enterprise-banner p-4 rounded-3xl text-white shadow-lg space-y-2 relative overflow-hidden"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2.5 min-w-0">
                        <ShopAvatar shop={{ id: 'active-shop', name: shopName, city: shopCity, image: null }} size={40} />
                        <div className="min-w-0">
                          <p className="text-[10px] uppercase tracking-wide text-blue-100">Boutique active</p>
                          <p className="text-sm font-bold truncate">{shopName}</p>
                        </div>
                      </div>
                      <span className="text-[10px] font-bold px-2.5 py-1 rounded-full bg-white/20 text-white backdrop-blur-sm flex-shrink-0">
                        {enterpriseInfo.subscriptionPlan}
                      </span>
                      <Building size={20} className="opacity-60" />
                    </div>
                    <div>
                      <h3 className="text-lg font-bold">{enterpriseInfo.companyName}</h3>
                      <p className="text-xs text-blue-100">📍 Siège : {enterpriseInfo.headOfficeCity}</p>
                    </div>
                    <div className="pt-2 flex items-center gap-3 border-t border-white/10 text-[11px] text-blue-100">
                      <span>NIU: <strong>{enterpriseInfo.niu || 'Non renseigné'}</strong></span>
                      <span>•</span>
                      <span>RCCM: <strong>{enterpriseInfo.rccm || 'Non renseigné'}</strong></span>
                    </div>
                  </div>

                  <div className="bg-white rounded-2xl border border-gray-100 p-3">
                    <Button onClick={() => setActiveSettingsSection('appearance')} className="w-full flex items-center justify-between text-left">
                      <span><strong className="block text-sm">Apparence</strong><span className="text-xs" style={{ color: 'var(--lk-text-secondary)' }}>Clair, sombre ou système</span></span><ChevronRight size={18} />
                    </Button>
                  </div>

                  <div className="bg-white rounded-2xl border border-gray-100 p-3">
                    <Button onClick={() => setActiveSettingsSection('catalogue')} className="w-full flex items-center justify-between text-left">
                      <span><strong className="block text-sm">Catalogue & images</strong><span className="text-xs" style={{ color: 'var(--lk-text-secondary)' }}>{catalogueDisplay === 'grid' ? 'Affichage en grille' : 'Affichage en liste'} · miniatures produit</span></span><ChevronRight size={18} />
                    </Button>
                  </div>

                  {/* Section Title */}
                  <p className="break-words text-xs font-bold text-gray-500 uppercase tracking-wide px-1">Options de gestion</p>

                  {/* 6 Settings Modules List */}
                  <div className="lk-settings-management-list divide-y divide-gray-100 border border-gray-100 rounded-2xl bg-white overflow-hidden shadow-sm">
                    {/* 1. Mon Entreprise */}
                    <Button
                      onClick={() => {
                        setEditEnterpriseCompanyName(enterpriseInfo.companyName)
                        setEditEnterpriseNiu(enterpriseInfo.niu || '')
                        setEditEnterpriseRccm(enterpriseInfo.rccm || '')
                        setEditEnterpriseHeadCity(enterpriseInfo.headOfficeCity)
                        setActiveSettingsSection('enterprise')
                      }}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center">
                          <Building size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Mon Entreprise</p>
                          <p className="break-words text-[11px] text-gray-400">Informations globales & abonnement</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>

                    {/* 2. Gérer mes boutiques */}
                    <Button
                      onClick={() => {
                        setSettingsModalOpen(false)
                        setSelectedShopId(null)
                        setOwnerSpaceOpen(true)
                      }}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center">
                          <Store size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Gérer mes boutiques</p>
                          <p className="break-words text-[11px] text-gray-400">{shops.length} établissements actifs</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>

                    {/* 3. Secteur d'activité */}
                    <Button
                      onClick={() => setActiveSettingsSection('sector')}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-amber-50 text-amber-600 flex items-center justify-center">
                          <Package size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Secteur d'activité</p>
                          <p className="break-words text-[11px] text-gray-400">Modèles de catalogues & métiers</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>

                    {/* 4. Appareils connectés */}
                    <Button
                      onClick={() => setActiveSettingsSection('devices')}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center">
                          <Smartphone size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Appareils connectés</p>
                          <p className="break-words text-[11px] text-gray-400">Caisses POS & terminaux autorisés</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>

                    {/* 5. Modules activés */}
                    <Button
                      onClick={() => setActiveSettingsSection('modules')}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-indigo-50 text-indigo-600 flex items-center justify-center">
                          <Zap size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Modules activés</p>
                          <p className="break-words text-[11px] text-gray-400">Vente crédit, OCR, Multi-panier</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>

                    {/* 6. Synchronisation locale */}
                    <Button
                      onClick={() => setActiveSettingsSection('sync')}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-sky-50 text-sky-600 flex items-center justify-center">
                          <RefreshCw size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Synchronisation locale</p>
                          <p className="break-words text-[11px] text-gray-400">Cache offline & sauvegarde cloud</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>

                    <Button
                      onClick={() => setActiveSettingsSection('commerce')}
                      className="lk-settings-management-row min-h-16 w-full p-3.5 flex items-center justify-between gap-3 text-left hover:bg-gray-50 cursor-pointer transition-colors"
                    >
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <div className="w-10 h-10 shrink-0 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center">
                          <ClipboardList size={20} />
                        </div>
                        <div className="min-w-0">
                          <p className="break-words text-xs font-bold text-gray-900">Règles de commerce</p>
                          <p className="break-words text-[11px] text-gray-400">Commandes PWA, stock, rôles et confidentialité</p>
                        </div>
                      </div>
                      <ChevronRight size={16} color="#98A2B3" className="shrink-0" />
                    </Button>
                  </div>
                </div>
              )}

              {activeSettingsSection === 'appearance' && <ThemePicker />}

              {activeSettingsSection === 'catalogue' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="rounded-2xl border border-blue-100 bg-blue-50 p-3 text-xs leading-relaxed text-blue-950">
                    Le mode Grille/Liste s’applique aux catalogues de vente, de stock et à la vitrine PWA. La visibilité des images ci-dessous concerne uniquement le catalogue interne.
                  </div>
                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">Affichage du catalogue</legend>
                    <p className="text-xs text-gray-500">Choisissez une vue confortable pour votre rythme de travail.</p>
                    {[
                      ['grid', 'Mode grille', 'Deux produits par ligne, avec une lecture complète du nom.'],
                      ['list', 'Mode liste', 'Une ligne extensible par produit, pratique pour comparer le stock et le prix.'],
                    ].map(([value, label, description]) => (
                      <label key={value} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${catalogueDisplay === value ? 'border-blue-500 bg-blue-50' : 'border-gray-200'}`}>
                        <Input type="radio" name="catalogue-display" value={value} checked={catalogueDisplay === value} onChange={() => setCatalogueDisplayPreference(value as 'grid' | 'list')} />
                        <span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span>
                      </label>
                    ))}
                  </fieldset>
                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">Images des cartes internes</legend>
                    <p className="text-xs leading-5 text-gray-500">Ce choix concerne Vente et Stock. La vitrine client conserve ses images produit.</p>
                    {[
                      [true, 'Avec miniatures', 'L’image est contenue dans un cadre dédié ; le nom reste intégralement lisible.'],
                      [false, 'Sans image — lecture prioritaire', 'L’espace est entièrement réservé au nom, au code, au prix et au stock.'],
                    ].map(([value, label, description]) => (
                      <label key={String(value)} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${showInternalCatalogueImages === value ? 'border-blue-500 bg-blue-50' : 'border-gray-200'}`}>
                        <Input type="radio" name="internal-catalogue-images" checked={showInternalCatalogueImages === value} onChange={() => setInternalCatalogueImagesPreference(value as boolean)} />
                        <span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span>
                      </label>
                    ))}
                  </fieldset>
                  <Button onClick={() => { showToast(`Catalogue en ${catalogueDisplay === 'grid' ? 'grille' : 'liste'} enregistré pour cet appareil.`); setActiveSettingsSection('index') }} className="w-full rounded-2xl bg-blue-600 py-3.5 text-xs font-bold text-white shadow-md">Enregistrer l’affichage</Button>
                </div>
              )}

              {/* ── SECTION 1: MON ENTREPRISE ── */}
              {activeSettingsSection === 'enterprise' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <h3 className="font-bold text-gray-900 text-sm">Informations de l'Entreprise</h3>

                    <div>
                      <label className="text-xs font-bold text-gray-700">Raison Sociale / Nom du groupe</label>
                      <Input
                        type="text"
                        value={editEnterpriseCompanyName}
                        onChange={(e) => setEditEnterpriseCompanyName(e.target.value)}
                        placeholder="Ex: Groupe Lynkstor Sarl"
                        className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-xs font-semibold outline-none"
                      />
                    </div>

                    <div>
                      <label className="text-xs font-bold text-gray-700">Ville du siège social</label>
                      <Input
                        type="text"
                        value={editEnterpriseHeadCity}
                        onChange={(e) => setEditEnterpriseHeadCity(e.target.value)}
                        placeholder="Ex: Douala"
                        className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-xs font-semibold outline-none"
                      />
                    </div>

                    <div>
                      <label className="text-xs font-bold text-gray-700">NIU (Numéro Identifiant Unique)</label>
                      <Input
                        type="text"
                        value={editEnterpriseNiu}
                        onChange={(e) => setEditEnterpriseNiu(e.target.value)}
                        placeholder="Ex: M051212345678A"
                        className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-xs font-semibold outline-none"
                      />
                    </div>

                    <div>
                      <label className="text-xs font-bold text-gray-700">RCCM (Registre du Commerce)</label>
                      <Input
                        type="text"
                        value={editEnterpriseRccm}
                        onChange={(e) => setEditEnterpriseRccm(e.target.value)}
                        placeholder="Ex: RC/DLA/2023/B/1234"
                        className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-xs font-semibold outline-none"
                      />
                    </div>

                    <div className="p-3 bg-amber-50/70 border border-amber-100 rounded-2xl flex items-start gap-2.5 text-xs text-amber-900">
                      <Info size={16} color="#F79009" className="flex-shrink-0 mt-0.5" />
                      <p className="leading-relaxed text-[11px]">
                        💡 Ces identifiants légaux (NIU, RCCM) sont uniques pour l'ensemble des boutiques de votre entreprise. Ils figurent sur tous vos reçus et factures d'encaissement.
                      </p>
                    </div>

                    <Button
                      disabled={!editEnterpriseCompanyName.trim()}
                      onClick={() => {
                        setEnterpriseInfo({
                          ...enterpriseInfo,
                          companyName: editEnterpriseCompanyName.trim(),
                          headOfficeCity: editEnterpriseHeadCity.trim(),
                          niu: editEnterpriseNiu.trim() || undefined,
                          rccm: editEnterpriseRccm.trim() || undefined,
                        })
                        showToast("Informations de l'entreprise mises à jour !")
                        setActiveSettingsSection('index')
                      }}
                      className="w-full py-3.5 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-all shadow-md disabled:opacity-40"
                    >
                      Enregistrer les modifications
                    </Button>
                  </div>
                </div>
              )}

              {/* ── SECTION 3: SECTEUR D'ACTIVITÉ ── */}
              {activeSettingsSection === 'sector' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <h3 className="font-bold text-gray-900 text-sm">Modèles sectoriels activés</h3>
                    <p className="text-xs text-gray-500">
                      Secteurs configurés pour alimenter les catalogues de produits de vos établissements :
                    </p>
                    <div className="grid grid-cols-2 gap-2 pt-1">
                      {SECTORS.map((sec) => (
                        <div
                          key={sec.id}
                          className="p-3 rounded-2xl border border-blue-100 bg-blue-50/50 text-center"
                        >
                          <span className="text-2xl block mb-1">{sec.emoji}</span>
                          <span className="text-xs font-bold text-gray-900 block">{sec.name}</span>
                          <span className="text-[10px] text-blue-700 font-medium mt-0.5 block">{sec.categories.length} catégories</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* ── SECTION 4: APPAREILS CONNECTÉS ── */}
              {activeSettingsSection === 'devices' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <h3 className="font-bold text-gray-900 text-sm">Appareils autorisés</h3>
                    <div className="divide-y divide-gray-100 border border-gray-100 rounded-xl overflow-hidden">
                      <div className="p-3 flex items-center justify-between">
                        <div className="flex items-center gap-2.5">
                          <Smartphone size={18} className="text-blue-600" />
                          <div>
                            <p className="text-xs font-bold text-gray-900">Caisse POS Akwa (Cet appareil)</p>
                            <p className="text-[10px] text-gray-400">Android POS · Douala</p>
                          </div>
                        </div>
                        <span className="px-2 py-0.5 rounded-full text-[9px] font-bold bg-green-100 text-green-700">En ligne</span>
                      </div>
                      <div className="p-3 flex items-center justify-between">
                        <div className="flex items-center gap-2.5">
                          <Smartphone size={18} className="text-gray-400" />
                          <div>
                            <p className="text-xs font-bold text-gray-900">Mobile POS Mokolo</p>
                            <p className="text-[10px] text-gray-400">Smartphone Android · Yaoundé</p>
                          </div>
                        </div>
                        <span className="px-2 py-0.5 rounded-full text-[9px] font-bold bg-gray-100 text-gray-600">Synchro il y a 5 min</span>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* ── SECTION 5: MODULES ACTIVÉS (RESTRUCTURÉS PAR FORFAIT) ── */}
              {activeSettingsSection === 'modules' && (
                <div className="space-y-4 animate-in fade-in duration-150 font-sans">
                  {/* Active Subscription Badge Header */}
                  <div className="p-3.5 bg-gradient-to-r from-slate-900 via-indigo-950 to-purple-950 text-white rounded-2xl flex items-center justify-between shadow-sm border border-slate-800">
                    <div>
                      <p className="text-[10px] font-extrabold text-indigo-300 uppercase tracking-wider">Abonnement Actuel POS</p>
                      <h4 className="text-sm font-extrabold text-white mt-0.5">Lynkstor Pro Business</h4>
                      <p className="text-[10px] text-slate-300">Modules débloqués & options configurables</p>
                    </div>
                    <Button
                      onClick={() => setSubscriptionPlansModalOpen(true)}
                      className="px-2.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white text-[10px] font-extrabold transition-all shadow-xs cursor-pointer"
                    >
                      Changer de forfait
                    </Button>
                  </div>

                  {/* Plan Tabs Selector */}
                  <div className="flex bg-gray-100 p-1 rounded-2xl border border-gray-200/80">
                    {[
                      { key: 'starter', label: '🟢 Starter', desc: 'Gratuit' },
                      { key: 'essential', label: '🔵 Essential', desc: 'Gestion Z' },
                      { key: 'pro', label: '🟣 Pro', desc: 'IA & Marges' },
                      { key: 'business', label: '👑 Business', desc: 'Multi-sites' },
                    ].map((plan) => (
                      <Button
                        key={plan.key}
                        onClick={() => setSelectedPlanTab(plan.key as typeof selectedPlanTab)}
                        className={`flex-1 py-2 rounded-xl text-center transition-all cursor-pointer ${selectedPlanTab === plan.key
                          ? 'bg-white text-indigo-600 font-extrabold shadow-2xs'
                          : 'text-gray-500 hover:text-gray-800 font-bold'
                          }`}
                      >
                        <p className="text-[11px] leading-tight">{plan.label}</p>
                      </Button>
                    ))}
                  </div>

                  {/* Feature Toggles List per Selected Plan Tab */}
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <div className="flex items-center justify-between border-b border-gray-100 pb-2">
                      <h3 className="font-bold text-gray-900 text-xs uppercase tracking-wider">
                        {selectedPlanTab === 'starter' && 'Modules Forfait Starter (Entrée de gamme)'}
                        {selectedPlanTab === 'essential' && 'Modules Forfait Essential (Gestion Financière)'}
                        {selectedPlanTab === 'pro' && 'Modules Forfait Pro (IA & Analyse Marges/OPEX)'}
                        {selectedPlanTab === 'business' && 'Modules Forfait Business (Multi-Boutiques Groupe)'}
                      </h3>
                    </div>

                    <div className="space-y-2">
                      {(() => {
                        const PLAN_MODULES: Record<typeof selectedPlanTab, { key: string; title: string; desc: string; badge?: string }[]> = {
                          starter: [
                            { key: 'expressPos', title: 'Vente Express & Encaissement Rapide', desc: 'Clavier tactile rapide & encaissement direct', badge: 'DE BASE' },
                            { key: 'barcodeScanner', title: 'Scanner Code-Barres par Caméra', desc: 'Scan instantané sans douchette matérielle', badge: 'DE BASE' },
                            { key: 'creditSale', title: 'Carnet de Dette & Ventes à Crédit', desc: 'Gestion des créances et rappels clients' },
                            { key: 'offlineMode', title: 'Mode 100% Hors Ligne & Base Locale', desc: 'Fonctionnement autonome sans connexion Internet' },
                            { key: 'expenseCashEntry', title: '💸 Dépenses : Saisie Cash Espèces', desc: 'Sorties de caisse quotidiennes en cash', badge: 'DÉPENSES' },
                          ],
                          essential: [
                            { key: 'cloudBackupSync', title: 'Sauvegarde Cloud & Synchro Multi-Appareils', desc: 'Synchronisation automatique et sécurisée' },
                            { key: 'cashClosureReportZ', title: 'Rapports de Clôture Caisse & Bilan Z', desc: 'Comptage des espèces et calcul des écarts' },
                            { key: 'expenseCategoryLedger', title: '💸 Dépenses : Registre 8 Catégories & Déduction Z', desc: 'Ventilation OPEX et déduction du solde cash caisse', badge: 'DÉPENSES' },
                            { key: 'multiPackPackaging', title: 'Conditionnements Multi-Niveaux', desc: 'Gestion des unités, cartons et paquets' },
                          ],
                          pro: [
                            { key: 'aiAssistant', title: 'Assistant Virtuel IA (Davex AI Companion)', desc: 'Conseils de vente, prédictions & statistiques' },
                            { key: 'invoiceOcr', title: 'OCR Factures & Numérisation Automatique', desc: 'Extraction automatique des pièces justificatives' },
                            { key: 'expenseNetProfitAnalysis', title: '💸 Dépenses : Bénéfice Net Réel & Ratio OPEX/CA', desc: 'Formule CA - COGS - OPEX et suivi rentabilité net', badge: 'DÉPENSES' },
                            { key: 'loyaltyPromotions', title: 'Programme Fidélité & Coupons Flash', desc: 'Calcul de points et réductions personnalisées' },
                          ],
                          business: [
                            { key: 'multiShopManagement', title: 'Pilotage Multi-Boutiques Centralisé', desc: 'Supervision globale de toutes les boutiques du groupe' },
                            { key: 'expenseMultiShopApproval', title: '💸 Dépenses : Consolidation Groupe & Rôles Validation', desc: 'Approbation des sorties par les responsables de site', badge: 'DÉPENSES' },
                            { key: 'multiUserPermissions', title: 'Gestion Multi-Utilisateurs & Profils Vendeurs', desc: 'Permissions fines Caisse, Stock et Supervision' },
                            { key: 'pushUssdMobileMoney', title: 'Paiement Mobile Money Push USSD Direct', desc: 'Encaissement automatique Orange, MTN & Wave' },
                          ],
                        }

                        return PLAN_MODULES[selectedPlanTab].map((m) => {
                          const isVal = enabledModules[m.key] ?? true
                          return (
                            <div
                              key={m.key}
                              onClick={() =>
                                setEnabledModules((prev) => ({
                                  ...prev,
                                  [m.key]: !prev[m.key],
                                }))
                              }
                              className={`p-3 rounded-2xl border transition-all cursor-pointer flex items-center justify-between ${isVal ? 'border-indigo-200 bg-indigo-50/40 shadow-2xs' : 'border-gray-100 bg-white'
                                }`}
                            >
                              <div className="space-y-0.5 pr-2">
                                <div className="flex items-center gap-2">
                                  <p className="text-xs font-bold text-gray-900">{m.title}</p>
                                  {m.badge && (
                                    <span className={`text-[9px] font-extrabold px-1.5 py-0.2 rounded-full ${m.badge === 'DÉPENSES' ? 'bg-rose-100 text-rose-700' : 'bg-blue-100 text-blue-700'
                                      }`}>
                                      {m.badge}
                                    </span>
                                  )}
                                </div>
                                <p className="text-[10px] text-gray-400">{m.desc}</p>
                              </div>
                              <Button className="text-indigo-600 flex-shrink-0">
                                {isVal ? <ToggleRight size={26} color="#4F46E5" /> : <ToggleLeft size={26} color="#98A2B3" />}
                              </Button>
                            </div>
                          )
                        })
                      })()}
                    </div>
                  </div>
                </div>
              )}

              {activeSettingsSection === 'commerce' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="rounded-2xl border border-emerald-100 bg-emerald-50 p-3 text-xs leading-relaxed text-emerald-950">
                    <strong>Décisions E0.</strong> Ces options définissent le comportement attendu du commerce dans cette démonstration. Elles doivent être appliquées et auditées par le service avant production.
                  </div>

                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">1. Données client</legend>
                    <p className="text-xs text-gray-500">Qui peut voir le nom et le téléphone complets d’un client ?</p>
                    {[['team_authorised', 'Équipe autorisée', 'Caisse, gestion et préparation selon le rôle.'], ['service_only', 'Service client seulement', 'Masquer les coordonnées dans les postes opérationnels.']].map(([value, label, description]) => <label key={value} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${commercePolicy.customerDataVisibility === value ? 'border-emerald-500 bg-emerald-50' : 'border-gray-200'}`}><Input type="radio" name="customer-data-visibility" value={value} checked={commercePolicy.customerDataVisibility === value} onChange={() => setCommercePolicy((policy) => ({ ...policy, customerDataVisibility: value as CommercePolicy['customerDataVisibility'] }))} /><span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span></label>)}
                  </fieldset>

                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">2. Réservation et sortie de stock</legend>
                    <p className="text-xs text-gray-500">À quel moment la commande PWA réserve-t-elle la quantité ?</p>
                    {[['acceptation', 'À l’acceptation', 'Réserver dès que la boutique confirme la commande.'], ['preparation', 'À la préparation', 'Réserver quand le magasinier commence la préparation.'], ['remise', 'À la remise', 'Ne réserver et sortir le stock qu’au retrait.']].map(([value, label, description]) => <label key={value} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${commercePolicy.stockReservationMoment === value ? 'border-emerald-500 bg-emerald-50' : 'border-gray-200'}`}><Input type="radio" name="stock-reservation" value={value} checked={commercePolicy.stockReservationMoment === value} onChange={() => setCommercePolicy((policy) => ({ ...policy, stockReservationMoment: value as CommercePolicy['stockReservationMoment'] }))} /><span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span></label>)}
                  </fieldset>

                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">3. Paiement des commandes PWA</legend>
                    {[['commande', 'Avant préparation', 'La commande attend un paiement confirmé avant traitement.'], ['remise', 'À la remise', 'Le client règle lors du retrait à la caisse.'], ['au_choix', 'Selon le choix du client', 'USSD ou règlement à la caisse, sans confirmation fictive.']].map(([value, label, description]) => <label key={value} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${commercePolicy.pwaPaymentMoment === value ? 'border-emerald-500 bg-emerald-50' : 'border-gray-200'}`}><Input type="radio" name="pwa-payment-moment" value={value} checked={commercePolicy.pwaPaymentMoment === value} onChange={() => setCommercePolicy((policy) => ({ ...policy, pwaPaymentMoment: value as CommercePolicy['pwaPaymentMoment'] }))} /><span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span></label>)}
                  </fieldset>

                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">4. Actions sensibles</legend>
                    <p className="text-xs text-gray-500">Qui valide une remise, annulation ou correction de stock hors seuil ?</p>
                    {[['proprietaire', 'Propriétaire uniquement', 'Contrôle central obligatoire.'], ['supervision', 'Supervision ou propriétaire', 'Le responsable de boutique peut valider.'], ['delegation', 'Délégation autorisée', 'Le propriétaire attribue explicitement les seuils.']].map(([value, label, description]) => <label key={value} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${commercePolicy.sensitiveActionApproval === value ? 'border-emerald-500 bg-emerald-50' : 'border-gray-200'}`}><Input type="radio" name="sensitive-actions" value={value} checked={commercePolicy.sensitiveActionApproval === value} onChange={() => setCommercePolicy((policy) => ({ ...policy, sensitiveActionApproval: value as CommercePolicy['sensitiveActionApproval'] }))} /><span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span></label>)}
                  </fieldset>

                  <fieldset className="space-y-3 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                    <legend className="px-1 text-sm font-bold text-gray-900">5. Rôles d’une même personne</legend>
                    {[['un_role_actif', 'Un rôle actif à la fois', 'La personne choisit son espace avant de travailler.'], ['roles_cumules', 'Permissions cumulées', 'Les autorisations attribuées sont réunies dans le même espace.']].map(([value, label, description]) => <label key={value} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 ${commercePolicy.workspaceMode === value ? 'border-emerald-500 bg-emerald-50' : 'border-gray-200'}`}><Input type="radio" name="workspace-mode" value={value} checked={commercePolicy.workspaceMode === value} onChange={() => setCommercePolicy((policy) => ({ ...policy, workspaceMode: value as CommercePolicy['workspaceMode'] }))} /><span><strong className="block text-xs text-gray-900">{label}</strong><span className="text-[11px] text-gray-500">{description}</span></span></label>)}
                  </fieldset>

                  <Button onClick={() => { showToast('Règles de commerce enregistrées dans cette démonstration.'); setActiveSettingsSection('index') }} className="w-full rounded-2xl bg-emerald-600 py-3.5 text-xs font-bold text-white shadow-md">Enregistrer les règles</Button>
                </div>
              )}

              {/* ── SECTION 6: SYNCHRONISATION LOCALE ── */}
              {activeSettingsSection === 'sync' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                    <h3 className="font-bold text-gray-900 text-sm">État de la Synchronisation</h3>

                    <div className="p-3 bg-gray-50 rounded-xl space-y-2 text-xs">
                      <div className="flex justify-between">
                        <span className="text-gray-500">Données en cache local :</span>
                        <span className="font-bold text-gray-900">2.4 MB (350 articles & ventes)</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-500">Dernière synchro Cloud :</span>
                        <span className="font-bold text-gray-900">{lastSyncTime}</span>
                      </div>
                    </div>

                    <Button
                      disabled={isSyncing}
                      onClick={() => {
                        setIsSyncing(true)
                        setTimeout(() => {
                          setIsSyncing(false)
                          setLastSyncTime("Simulation terminée à l’instant")
                          showToast("Simulation terminée : aucun moteur cloud n’est connecté.")
                        }, 1200)
                      }}
                      className="w-full py-3.5 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-all shadow-md flex items-center justify-center gap-2 disabled:opacity-50" aria-label="Actualiser"
                    >
                      <RefreshCw size={16} className={isSyncing ? 'animate-spin' : ''} />
                      <span>{isSyncing ? 'Simulation en cours…' : 'Simuler une synchronisation'}</span>
                    </Button>
                    <div className="flex items-center gap-2 rounded-xl border border-sky-100 bg-sky-50 px-3 py-2 text-xs" role="status" aria-live="polite">
                      <span className={`w-2 h-2 rounded-full ${syncTransport === 'cloud' ? 'bg-emerald-500' : syncTransport === 'wifi' ? 'bg-sky-500' : 'bg-gray-400'}`} />
                      <span className="font-semibold text-sky-900">
                        État actuel : {syncTransport === 'cloud' ? 'Cloud synchronisé' : syncTransport === 'wifi' ? 'Appareil voisin synchronisé' : 'Local uniquement'}
                      </span>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </Dialog>
        )}

        {/* ── MODAL: NOUVELLE BOUTIQUE (MINI-PARCOURS 4 ÉTAPES) ── */}
        {createShopModalOpen && (
          <Dialog
            className="absolute inset-0 z-50 flex items-center justify-center px-4"
            style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(3px)' }}
            onClick={() => setCreateShopModalOpen(false)} label="Nouvelle boutique" onDismiss={() => setCreateShopModalOpen(false)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200 max-h-[90vh] overflow-y-auto"
              onClick={(e) => e.stopPropagation()}
            >
              {/* Header */}
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Ajouter une boutique</h3>
                  <p className="text-xs text-blue-600 font-medium">Étape {createShopStep} sur 4</p>
                </div>
                <Button onClick={() => setCreateShopModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              {/* Progress dots */}
              <div className="flex gap-1.5 justify-center py-1">
                {[1, 2, 3, 4].map((step) => (
                  <div
                    key={step}
                    className={`h-1.5 rounded-full transition-all ${createShopStep === step ? 'w-8 bg-blue-600' : createShopStep > step ? 'w-4 bg-blue-300' : 'w-4 bg-gray-200'
                      }`}
                  />
                ))}
              </div>

              {/* STEP 1: Nom & Ville */}
              {createShopStep === 1 && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div>
                    <label className="text-xs font-bold text-gray-700">Nom de la boutique</label>
                    <Input
                      type="text"
                      value={newShopName}
                      onChange={(e) => setNewShopName(e.target.value)}
                      placeholder="Ex: Lynkstor Express Akwa"
                      className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                      autoFocus
                    />
                  </div>
                  <div>
                    <label className="text-xs font-bold text-gray-700">Ville</label>
                    <Input
                      type="text"
                      value={newShopCity}
                      onChange={(e) => setNewShopCity(e.target.value)}
                      placeholder="Ex: Douala, Yaoundé, Garoua..."
                      className="w-full mt-1 bg-gray-100 rounded-xl px-3 py-3 text-sm font-semibold outline-none"
                    />
                  </div>
                  <Button
                    disabled={!newShopName.trim() || !newShopCity.trim()}
                    onClick={() => {
                      setCreateShopStep(2)
                    }}
                    className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-blue-600 active:scale-95 transition-all disabled:opacity-40 shadow-md mt-2"
                  >
                    Continuer — Sélectionner le secteur
                  </Button>
                </div>
              )}

              {/* STEP 2: Sélection Secteur */}
              {createShopStep === 2 && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div>
                    <p className="text-xs font-bold text-gray-900">Secteur d'activité</p>
                    <p className="text-[11px] text-gray-400 mt-0.5">Chaque boutique a son propre secteur.</p>
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    {SECTORS.map((sec) => {
                      const isSelected = newShopSector === sec.name
                      return (
                        <Button
                          key={sec.id}
                          onClick={() => {
                            setNewShopSector(sec.name)
                            setNewShopCategories(sec.categories)
                          }}
                          className={`p-3 rounded-2xl border-2 transition-all cursor-pointer text-center ${isSelected ? 'border-[#0050FF] bg-[#EFF4FF] shadow-sm' : 'border-gray-100 bg-white hover:border-gray-200'
                            }`}
                        >
                          <span className="text-2xl block mb-1">{sec.emoji}</span>
                          <span className="text-xs font-bold text-gray-900 block">{sec.name}</span>
                        </Button>
                      )
                    })}
                  </div>
                  <div className="flex gap-2 pt-2">
                    <Button
                      onClick={() => setCreateShopStep(1)}
                      className="flex-1 py-3 rounded-2xl bg-gray-100 text-gray-700 font-bold text-xs"
                    >
                      Retour
                    </Button>
                    <Button
                      onClick={() => setCreateShopStep(3)}
                      className="flex-1 py-3.5 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-all shadow-md"
                    >
                      Continuer
                    </Button>
                  </div>
                </div>
              )}

              {/* STEP 3: Sélection Catégories */}
              {createShopStep === 3 && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div>
                    <p className="text-xs font-bold text-gray-900">Catégories d'articles</p>
                    <p className="text-[11px] text-gray-400 mt-0.5">Pré-sélectionnées pour le secteur {newShopSector}</p>
                  </div>
                  <div className="space-y-2 max-h-48 overflow-y-auto">
                    {(SECTORS.find((s) => s.name === newShopSector)?.categories || ['Général']).map((cat) => {
                      const isChecked = newShopCategories.includes(cat)
                      return (
                        <Button
                          key={cat}
                          onClick={() => {
                            setNewShopCategories((prev) =>
                              isChecked ? prev.filter((c) => c !== cat) : [...prev, cat]
                            )
                          }}
                          className={`p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between ${isChecked ? 'border-blue-200 bg-blue-50/50 text-blue-900 font-bold' : 'border-gray-100 bg-white text-gray-500'
                            }`}
                        >
                          <span className="text-xs">{cat}</span>
                          {isChecked && <Check size={16} color="#0050FF" />}
                        </Button>
                      )
                    })}
                  </div>
                  <div className="flex gap-2 pt-2">
                    <Button
                      onClick={() => setCreateShopStep(2)}
                      className="flex-1 py-3 rounded-2xl bg-gray-100 text-gray-700 font-bold text-xs"
                    >
                      Retour
                    </Button>
                    <Button
                      onClick={() => setCreateShopStep(4)}
                      className="flex-1 py-3.5 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-all shadow-md"
                    >
                      Continuer
                    </Button>
                  </div>
                </div>
              )}

              {/* STEP 4: Confirmation & Identité Légale du Groupe */}
              {createShopStep === 4 && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div>
                    <p className="text-xs font-bold text-gray-900">Identité Légale du Groupe</p>
                    <p className="text-[11px] text-gray-400 mt-0.5">Cette boutique est rattachée aux identifiants du groupe</p>
                  </div>

                  <div className="bg-gray-50 rounded-2xl p-3.5 space-y-2 border border-gray-100 text-xs">
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500 font-medium">Raison sociale :</span>
                      <span className="font-bold text-gray-900">{enterpriseInfo.companyName}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500 font-medium">NIU (Unique) :</span>
                      <span className="font-bold text-gray-900">{enterpriseInfo.niu || 'Non renseigné'}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500 font-medium">RCCM (Unique) :</span>
                      <span className="font-bold text-gray-900">{enterpriseInfo.rccm || 'Non renseigné'}</span>
                    </div>
                  </div>

                  <div className="p-3 bg-blue-50/70 border border-blue-100 rounded-2xl flex items-start gap-2.5 text-xs text-blue-900">
                    <Info size={16} color="#0050FF" className="flex-shrink-0 mt-0.5" />
                    <p className="leading-relaxed text-[11px]">
                      💡 Les informations légales sont uniques pour l'entreprise et modifiables à tout moment depuis <strong>Paramètres → Mon Entreprise</strong>.
                    </p>
                  </div>

                  <div className="flex gap-2 pt-2">
                    <Button
                      onClick={() => setCreateShopStep(3)}
                      className="flex-1 py-3 rounded-2xl bg-gray-100 text-gray-700 font-bold text-xs"
                    >
                      Retour
                    </Button>
                    <Button
                      onClick={() => {
                        const createdShop: ShopOwnerItem = {
                          id: `shop-${Date.now()}`,
                          name: newShopName.trim(),
                          city: newShopCity.trim(),
                          hours: { openTime: '08:00', closeTime: '20:00', days: 'Lun - Sam' },
                          revenue7d: 0,
                          sector: newShopSector,
                          staff: [],
                        }
                        setShops((prev) => [...prev, createdShop])
                        showToast(`Boutique "${newShopName.trim()}" créée avec succès !`)
                        setCreateShopModalOpen(false)
                      }}
                      className="flex-1 py-3.5 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-all shadow-md"
                    >
                      Créer cette boutique
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </Dialog>
        )}



        {/* ── TOAST NOTIFICATION FLOATING BANNER ── */}
        {toastMessage && (
          <div className="absolute top-16 left-4 right-4 z-50 bg-gray-900 text-white text-xs font-bold px-4 py-3 rounded-2xl shadow-xl flex items-center gap-2 animate-in fade-in slide-in-from-top-2 duration-200">
            <CheckCircle size={16} color="#12B76A" />
            <span>{toastMessage}</span>
          </div>
        )}

        {/* Notifications Modal */}
        {notificationsOpen && (
          <Dialog
            className="absolute inset-0 z-50 flex items-start justify-center pt-16 px-4"
            style={{ backgroundColor: 'rgba(0,0,0,0.4)', backdropFilter: 'blur(2px)' }}
            onClick={() => setNotificationsOpen(false)} label="Notifications" onDismiss={() => setNotificationsOpen(false)}
          >
            <div
              className="w-full bg-white rounded-2xl shadow-xl overflow-hidden animate-in fade-in slide-in-from-top-4 duration-200"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100 bg-gray-50">
                <div className="flex items-center gap-2">
                  <Bell size={18} color="#0050FF" />
                  <span className="font-bold text-gray-900 text-sm">Notifications</span>
                  <span className="bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full">2</span>
                </div>
                <Button
                  onClick={() => setNotificationsOpen(false)}
                  className="p-1 rounded-lg hover:bg-gray-200 text-gray-400 hover:text-gray-600 transition-colors" aria-label="Fermer"
                >
                  <X size={18} />
                </Button>
              </div>
              <div className="divide-y divide-gray-100 max-h-72 overflow-y-auto">
                <div className="p-3 hover:bg-amber-50/50 transition-colors flex items-start gap-3">
                  <div className="w-8 h-8 rounded-xl bg-red-100 flex items-center justify-center text-red-600 flex-shrink-0 mt-0.5">
                    <AlertTriangle size={16} />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs font-bold text-gray-900">Stock critique — Sucre 1kg</p>
                    <p className="text-[11px] text-gray-500 mt-0.5">Il ne reste plus que 2 unités en magasin.</p>
                    <span className="text-[10px] text-gray-400 mt-1 block">Il y a 10 min</span>
                  </div>
                </div>

                <div className="p-3 hover:bg-amber-50/50 transition-colors flex items-start gap-3">
                  <div className="w-8 h-8 rounded-xl bg-amber-100 flex items-center justify-center text-amber-600 flex-shrink-0 mt-0.5">
                    <AlertTriangle size={16} />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs font-bold text-gray-900">Stock bas — Riz Basmati 5kg</p>
                    <p className="text-[11px] text-gray-500 mt-0.5">Stock à 7 unités (seuil réassort : 10).</p>
                    <span className="text-[10px] text-gray-400 mt-1 block">Il y a 30 min</span>
                  </div>
                </div>

                <div className="p-3 hover:bg-gray-50 transition-colors flex items-start gap-3">
                  <div className="w-8 h-8 rounded-xl bg-green-100 flex items-center justify-center text-green-600 flex-shrink-0 mt-0.5">
                    <CheckCircle size={16} />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs font-bold text-gray-900">Synchronisation réussie</p>
                    <p className="text-[11px] text-gray-500 mt-0.5">Boutique "{shopName}" ({sector} · {shopCity}) synchronisée.</p>
                    <span className="text-[10px] text-gray-400 mt-1 block">Il y a 1h</span>
                  </div>
                </div>
              </div>
              <div className="p-2.5 bg-gray-50 border-t border-gray-100 flex items-center justify-between px-4">
                <Button
                  onClick={onResetOnboarding}
                  className="text-xs font-medium text-gray-500 hover:text-gray-700"
                >
                  ⚙️ Re-tester l'onboarding
                </Button>
                <Button
                  onClick={() => setNotificationsOpen(false)}
                  className="text-xs font-bold text-blue-600 hover:text-blue-700"
                >
                  Tout marquer comme lu
                </Button>
              </div>
            </div>
          </Dialog>
        )}

        {/* ── MODULE 7: MODAL REPORTING, MARGES & PERFORMANCE ── */}
        {reportingModalOpen && (
          <Dialog className="lk-reporting-modal absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200" label="Rapports" onDismiss={() => setReportingModalOpen(false)}>
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => setReportingModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Rapports & Marges</h2>
                <p className="text-[11px] text-blue-600 font-medium">{reportingRange === 'jour' ? 'Performance du jour' : reportingRange === 'semaine' ? 'Performance de la semaine' : 'Performance du mois'} · {reportingScope === 'active' ? shopName : 'Toutes les boutiques'}</p>
              </div>
              <Button
                onClick={() => setReportingModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            <div className="p-4 space-y-4 flex-1">
              <div className="lk-reporting-scope grid grid-cols-2 gap-2 rounded-2xl border border-gray-100 bg-gray-50 p-1.5" aria-label="Périmètre du rapport">
                <Select
                  value={reportingRange}
                  onChange={(e) => setReportingRange(e.target.value as typeof reportingRange)}
                  aria-label="Période du rapport"
                  className="rounded-xl border-0 bg-white px-3 py-2 text-xs font-bold text-gray-800 outline-none"
                >
                  <option value="jour">Aujourd’hui</option>
                  <option value="semaine">Cette semaine</option>
                  <option value="mois">Ce mois</option>
                </Select>
                <Select
                  value={reportingScope}
                  onChange={(e) => setReportingScope(e.target.value as typeof reportingScope)}
                  aria-label="Boutique du rapport"
                  className="rounded-xl border-0 bg-white px-3 py-2 text-xs font-bold text-gray-800 outline-none"
                >
                  <option value="active">Boutique active</option>
                  <option value="all">Toutes les boutiques</option>
                </Select>
              </div>
              <p className="lk-reporting-demo rounded-xl border border-blue-100 bg-blue-50 px-3 py-2 text-[11px] text-blue-900">
                Vue de démonstration : le périmètre est mémorisé dans l’interface ; les données consolidées seront branchées au service de rapports.
              </p>

              {/* 4 KPIs grid */}
              <div className="grid grid-cols-2 gap-3">
                <div className="lk-reporting-kpi lk-reporting-kpi--revenue p-3.5 bg-blue-50/60 border border-blue-100 rounded-2xl">
                  <p className="text-[10px] font-bold text-blue-700 uppercase tracking-wide">CA du jour</p>
                  <p className="text-lg font-bold text-gray-900 mt-0.5">142 500 <span className="text-xs font-normal text-gray-500">FCFA</span></p>
                  <p className="text-[10px] text-green-600 font-medium mt-1">▲ +14% vs hier</p>
                </div>
                <div className="lk-reporting-kpi lk-reporting-kpi--margin p-3.5 bg-emerald-50/60 border border-emerald-100 rounded-2xl">
                  <p className="text-[10px] font-bold text-emerald-700 uppercase tracking-wide">Marge brute du jour</p>
                  <p className="text-lg font-bold text-gray-900 mt-0.5">40 612 <span className="text-xs font-normal text-gray-500">FCFA</span></p>
                  <p className="text-[10px] text-emerald-700 font-medium mt-1">Taux de marge : 28.5%</p>
                </div>
                <div className="lk-reporting-kpi lk-reporting-kpi--sales p-3.5 bg-purple-50/60 border border-purple-100 rounded-2xl">
                  <p className="text-[10px] font-bold text-purple-700 uppercase tracking-wide">Nombre de ventes</p>
                  <p className="text-lg font-bold text-gray-900 mt-0.5">18 <span className="text-xs font-normal text-gray-500">tickets</span></p>
                  <p className="text-[10px] text-purple-700 font-medium mt-1">100% encaissés</p>
                </div>
                <div className="lk-reporting-kpi lk-reporting-kpi--basket p-3.5 bg-amber-50/60 border border-amber-100 rounded-2xl">
                  <p className="text-[10px] font-bold text-amber-700 uppercase tracking-wide">Panier moyen</p>
                  <p className="text-lg font-bold text-gray-900 mt-0.5">7 916 <span className="text-xs font-normal text-gray-500">FCFA</span></p>
                  <p className="text-[10px] text-amber-700 font-medium mt-1">~3.2 articles / client</p>
                </div>
              </div>

              {/* Ventes par tranche horaire */}
              <div className="lk-reporting-section bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                <div className="flex items-center justify-between">
                  <h3 className="font-bold text-gray-900 text-xs uppercase tracking-wide">Ventes par tranche horaire</h3>
                  <span className="text-[10px] font-bold text-blue-600">Aujourd'hui</span>
                </div>
                <div className="flex items-end justify-between gap-2 h-24 pt-2">
                  {[
                    { hour: '08h', val: 12000, h: '30%' },
                    { hour: '10h', val: 28500, h: '60%' },
                    { hour: '12h', val: 42000, h: '90%' },
                    { hour: '14h', val: 22000, h: '45%' },
                    { hour: '16h', val: 38000, h: '80%' },
                    { hour: '18h', val: 15000, h: '35%' },
                  ].map((t) => (
                    <div key={t.hour} className="flex-1 flex flex-col items-center gap-1">
                      <div
                        className="w-full rounded-t-lg bg-blue-600 hover:bg-blue-700 transition-all"
                        style={{ height: t.h }}
                      />
                      <span className="text-[9px] font-semibold text-gray-500">{t.hour}</span>
                    </div>
                  ))}
                </div>
              </div>

              {/* Top 5 Articles Rentables */}
              <div className="lk-reporting-section bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-1.5">
                    <Award size={16} className="text-amber-500" />
                    <h3 className="font-bold text-gray-900 text-xs uppercase tracking-wide">Top 5 Articles les plus vendus</h3>
                  </div>
                </div>

                <div className="divide-y divide-gray-100 border border-gray-100 rounded-xl overflow-hidden text-xs">
                  {[
                    { name: 'Huile Végétale 1L', qty: 24, ca: 36000, margin: '25%' },
                    { name: 'Riz Basmati 5kg', qty: 10, ca: 45000, margin: '20%' },
                    { name: 'Lait Concentré 1kg', qty: 15, ca: 22500, margin: '32%' },
                    { name: 'Sucre 1kg', qty: 20, ca: 15000, margin: '35%' },
                    { name: 'Eau Minérale 1.5L', qty: 8, ca: 24000, margin: '40%' },
                  ].map((item, idx) => (
                    <div key={item.name} className="p-2.5 flex items-center justify-between hover:bg-gray-50">
                      <div className="flex items-center gap-2">
                        <span className="w-5 h-5 rounded-full bg-blue-50 text-blue-700 font-bold text-[10px] flex items-center justify-center">
                          #{idx + 1}
                        </span>
                        <div>
                          <p className="font-bold text-gray-900">{item.name}</p>
                          <p className="text-[10px] text-gray-400">{item.qty} unités vendues</p>
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="font-bold text-gray-900">{item.ca.toLocaleString('fr-FR')} FCFA</p>
                        <p className="text-[10px] text-green-600 font-semibold">Marge : {item.margin}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Action Button: Generate Z Report Ticket */}
              <Button
                onClick={() => setReportingZReportOpen(true)}
                className="lk-reporting-export w-full py-3.5 rounded-2xl text-white font-bold text-xs bg-blue-600 active:scale-95 transition-all shadow-md flex items-center justify-center gap-2"
              >
                <Printer size={16} />
                <span>Aperçu & Exporter le Ticket Z de Caisse (PDF)</span>
              </Button>
            </div>
          </Dialog>
        )}

        {/* ── MODULE 8: MODAL CLÔTURE DE CAISSE (Z) & RAPPROCHEMENT ── */}
        {cashClosureModalOpen && (
          <Dialog className="lk-cash-closure-modal absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200" label="Clôture de caisse" onDismiss={() => setCashClosureModalOpen(false)}>
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => setCashClosureModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Clôture de Caisse (Z)</h2>
                <p className="text-[11px] text-emerald-600 font-medium">Comptage & Rapprochement d'Espèces</p>
              </div>
              <Button
                onClick={() => setCashClosureModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            <div className="p-4 space-y-4 flex-1">
              {/* Solde théorique en caisse */}
              <div className="p-4 bg-emerald-50 border border-emerald-100 rounded-2xl space-y-1">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-emerald-800 uppercase tracking-wide">Solde Théorique en Espèces</span>
                  <span className="px-2 py-0.5 rounded-full text-[9px] font-bold bg-emerald-200 text-emerald-900">Calcul Système</span>
                </div>
                <p className="text-2xl font-bold text-emerald-950">127 500 <span className="text-xs font-normal text-emerald-700">FCFA</span></p>
                <p className="text-[10px] text-emerald-800">Total ventes cash de la journée · 18 tickets</p>
              </div>

              {/* Saisie du comptage physique des billets/pièces */}
              <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3 shadow-sm">
                <h3 className="font-bold text-gray-900 text-xs uppercase tracking-wide">Comptage physique des billets & pièces</h3>

                <div className="space-y-2 text-xs">
                  <div className="flex items-center justify-between gap-3">
                    <span className="w-32 font-semibold text-gray-700">Billets de 10 000 F</span>
                    <Input
                      type="number"
                      value={cashBill10k}
                      onChange={(e) => setCashBill10k(e.target.value)}
                      className="w-20 bg-gray-100 rounded-xl px-3 py-2 text-center font-bold text-gray-900 outline-none"
                    />
                    <span className="w-24 text-right font-bold text-gray-900">{(10000 * Number(cashBill10k || 0)).toLocaleString('fr-FR')} F</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="w-32 font-semibold text-gray-700">Billets de 5 000 F</span>
                    <Input
                      type="number"
                      value={cashBill5k}
                      onChange={(e) => setCashBill5k(e.target.value)}
                      className="w-20 bg-gray-100 rounded-xl px-3 py-2 text-center font-bold text-gray-900 outline-none"
                    />
                    <span className="w-24 text-right font-bold text-gray-900">{(5000 * Number(cashBill5k || 0)).toLocaleString('fr-FR')} F</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="w-32 font-semibold text-gray-700">Billets de 2 000 F</span>
                    <Input
                      type="number"
                      value={cashBill2k}
                      onChange={(e) => setCashBill2k(e.target.value)}
                      className="w-20 bg-gray-100 rounded-xl px-3 py-2 text-center font-bold text-gray-900 outline-none"
                    />
                    <span className="w-24 text-right font-bold text-gray-900">{(2000 * Number(cashBill2k || 0)).toLocaleString('fr-FR')} F</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="w-32 font-semibold text-gray-700">Billets de 1 000 F</span>
                    <Input
                      type="number"
                      value={cashBill1k}
                      onChange={(e) => setCashBill1k(e.target.value)}
                      className="w-20 bg-gray-100 rounded-xl px-3 py-2 text-center font-bold text-gray-900 outline-none"
                    />
                    <span className="w-24 text-right font-bold text-gray-900">{(1000 * Number(cashBill1k || 0)).toLocaleString('fr-FR')} F</span>
                  </div>

                  <div className="flex items-center justify-between gap-3 pt-1 border-t border-gray-100">
                    <span className="w-32 font-semibold text-gray-700">Pièces de monnaie</span>
                    <Input
                      type="number"
                      value={cashCoins}
                      onChange={(e) => setCashCoins(e.target.value)}
                      placeholder="FCFA"
                      className="w-20 bg-gray-100 rounded-xl px-3 py-2 text-center font-bold text-gray-900 outline-none"
                    />
                    <span className="w-24 text-right font-bold text-gray-900">{Number(cashCoins || 0).toLocaleString('fr-FR')} F</span>
                  </div>
                </div>
              </div>

              {/* Rapprochement & Calcul de l'écart */}
              {(() => {
                const totalPhysical =
                  10000 * Number(cashBill10k || 0) +
                  5000 * Number(cashBill5k || 0) +
                  2000 * Number(cashBill2k || 0) +
                  1000 * Number(cashBill1k || 0) +
                  Number(cashCoins || 0)
                const theoretical = 127500
                const diff = totalPhysical - theoretical

                return (
                  <div className="space-y-3">
                    <div className="p-3.5 bg-gray-50 rounded-2xl border border-gray-100 flex items-center justify-between text-xs">
                      <span className="font-bold text-gray-700">Total physique compté :</span>
                      <span className="text-base font-bold text-gray-900">{totalPhysical.toLocaleString('fr-FR')} FCFA</span>
                    </div>

                    {diff === 0 ? (
                      <div className="p-3 bg-green-50 border border-green-200 rounded-2xl flex items-center gap-2 text-xs text-green-900 font-bold">
                        <CheckCircle size={18} color="#12B76A" />
                        <span>✅ Caisse parfaitement conforme (Écart : 0 FCFA)</span>
                      </div>
                    ) : diff < 0 ? (
                      <div className="p-3 bg-red-50 border border-red-200 rounded-2xl flex items-center gap-2 text-xs text-red-900 font-bold">
                        <AlertTriangle size={18} color="#F04438" />
                        <span>⚠️ Manquant en caisse : {diff.toLocaleString('fr-FR')} FCFA</span>
                      </div>
                    ) : (
                      <div className="p-3 bg-blue-50 border border-blue-200 rounded-2xl flex items-center gap-2 text-xs text-blue-900 font-bold">
                        <Info size={18} color="#0050FF" />
                        <span>ℹ️ Excédent en caisse : +{diff.toLocaleString('fr-FR')} FCFA</span>
                      </div>
                    )}

                    <Button
                      onClick={() => {
                        setCashClosureModalOpen(false)
                        setReportingZReportOpen(true)
                        showToast("Clôture de Caisse (Z) validée et verrouillée avec succès !")
                      }}
                      className="w-full py-3.5 rounded-2xl text-white font-bold text-xs bg-emerald-600 active:scale-95 transition-all shadow-md flex items-center justify-center gap-2"
                    >
                      <Lock size={16} />
                      <span>Valider & Verrouiller le Z de Caisse</span>
                    </Button>
                  </div>
                )
              })()}
            </div>
          </Dialog>
        )}

        {/* ── MODAL: APERÇU / IMPRESSION TICKET Z DE CAISSE (PDF) ── */}
        {reportingZReportOpen && (
          <Dialog
            className="absolute inset-0 z-50 flex items-center justify-center px-4"
            style={{ backgroundColor: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(3px)' }}
            onClick={() => setReportingZReportOpen(false)} label="Rapport Z" onDismiss={() => setReportingZReportOpen(false)}
          >
            <div
              className="lk-report-preview w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200 max-h-[90vh] overflow-y-auto"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Rapport Z de Caisse</h3>
                  <p className="text-xs text-blue-600 font-medium">Clôture du 25/07/2025</p>
                </div>
                <Button onClick={() => setReportingZReportOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              {/* Thermal Ticket Preview */}
              <div className="bg-gray-50 border border-dashed border-gray-300 rounded-2xl p-4 space-y-3 font-mono text-[11px] text-gray-800">
                <div className="text-center space-y-0.5 border-b border-gray-200 pb-2">
                  <p className="font-bold text-sm uppercase">{enterpriseInfo.companyName}</p>
                  <p>{shopName} · Douala</p>
                  <p>NIU: {enterpriseInfo.niu || 'M051212345678A'}</p>
                  <p className="font-bold pt-1">RAPPORT CLÔTURE DE CAISSE (Z)</p>
                  <p className="text-[10px] text-gray-400">Date: 25/07/2025 · 19:30</p>
                </div>

                <div className="space-y-1">
                  <div className="flex justify-between"><span>Ventes espèces :</span><span className="font-bold">127 500 FCFA</span></div>
                  <div className="flex justify-between"><span>Ventes Mobile Money :</span><span className="font-bold">15 000 FCFA</span></div>
                  <div className="flex justify-between border-t border-gray-200 pt-1 font-bold"><span>TOTAL CA :</span><span>142 500 FCFA</span></div>
                </div>

                <div className="space-y-1 border-t border-gray-200 pt-2">
                  <div className="flex justify-between"><span>Nombre de tickets :</span><span>18</span></div>
                  <div className="flex justify-between"><span>Marge brute globale :</span><span>40 612 FCFA (28.5%)</span></div>
                  <div className="flex justify-between text-green-700 font-bold"><span>Écart de caisse :</span><span>0 FCFA (Conforme)</span></div>
                </div>

                <div className="text-center text-[9px] text-gray-400 pt-2 border-t border-gray-200">
                  *** TICKET OFFICIEL LYNKSTOR CAISSE ***
                </div>
              </div>

              <div className="flex gap-2">
                <Button
                  onClick={() => {
                    showToast("Impression du ticket Z lancée...")
                    setTimeout(() => setReportingZReportOpen(false), 1000)
                  }}
                  className="flex-1 py-3 rounded-2xl bg-blue-600 text-white font-bold text-xs shadow-md flex items-center justify-center gap-1.5 active:scale-95"
                >
                  <Printer size={16} />
                  <span>Imprimer le Ticket</span>
                </Button>
                <Button
                  onClick={() => setReportingZReportOpen(false)}
                  className="px-4 py-3 rounded-2xl bg-gray-100 text-gray-700 font-bold text-xs"
                >
                  Fermer
                </Button>
              </div>
            </div>
          </Dialog>
        )}

        {/* ── MODAL: CARNET DE DETTE & RECOUVREMENT ── */}
        {creditLedgerModalOpen && (
          <Dialog className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200" label="Carnet de dette" onDismiss={() => setCreditLedgerModalOpen(false)}>
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => setCreditLedgerModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Carnet de Dette & Créances</h2>
                <p className="text-[11px] text-amber-600 font-medium">
                  {creditAccounts.reduce((sum, acc) => sum + getAccountBalance(acc), 0).toLocaleString('fr-FR')} FCFA à recouvrer
                </p>
              </div>
              <Button
                onClick={() => setCreditLedgerModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            <div className="p-4 space-y-4 flex-1">
              {/* Summary Card */}
              <div
                className="p-4 rounded-3xl text-white shadow-md space-y-1"
                style={{ background: 'linear-gradient(135deg, #D97706 0%, #B45309 100%)' }}
              >
                <p className="text-[10px] font-bold uppercase tracking-wider text-amber-100">Solde global des créances</p>
                <p className="text-2xl font-bold">
                  {creditAccounts.reduce((sum, acc) => sum + getAccountBalance(acc), 0).toLocaleString('fr-FR')} FCFA
                </p>
                <p className="text-xs text-amber-100 font-medium">{creditAccounts.length} comptes clients enregistrés</p>
              </div>

              {/* Debtors List */}
              <div className="space-y-3">
                <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Liste des comptes clients</p>
                {creditAccounts.map((acc) => {
                  const bal = getAccountBalance(acc)
                  return (
                    <div key={acc.id} className="bg-white rounded-2xl p-4 border border-gray-100 space-y-3 shadow-xs">
                      <div className="flex items-start justify-between">
                        <div>
                          <p className="text-sm font-bold text-gray-900">{acc.name}</p>
                          <p className="text-xs text-gray-400 mt-0.5">📞 {acc.phone ? `+237 ${acc.phone}` : 'Pas de téléphone'}</p>
                        </div>
                        <div className="text-right">
                          <p className={`text-base font-bold ${bal > 0 ? 'text-amber-700' : 'text-emerald-600'}`}>
                            {bal.toLocaleString('fr-FR')} FCFA
                          </p>
                          <span className={`inline-block text-[10px] font-bold px-2 py-0.5 rounded-full mt-0.5 ${bal > 0 ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'}`}>
                            {bal > 0 ? 'Impayé en cours' : 'Solde réglé'}
                          </span>
                        </div>
                      </div>

                      {/* Movements breakdown */}
                      <div className="bg-gray-50 rounded-xl p-2.5 space-y-1.5 text-xs">
                        <p className="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Derniers mouvements</p>
                        {acc.movements.slice(-3).map((m) => (
                          <div key={m.id} className="flex justify-between items-center text-[11px]">
                            <span className="text-gray-600">
                              {m.date} · {m.type === 'sale' ? 'Vente à crédit' : 'Remboursement'}
                            </span>
                            <span className={m.type === 'sale' ? 'font-bold text-amber-700' : 'font-bold text-emerald-600'}>
                              {m.type === 'sale' ? '+' : '-'}{m.amount.toLocaleString('fr-FR')} F
                            </span>
                          </div>
                        ))}
                      </div>

                      {/* Actions */}
                      <div className="flex gap-2 pt-1">
                        <Button
                          onClick={() => {
                            setRepaymentAccount(acc)
                            setRepaymentAmountInput(bal > 0 ? String(bal) : '1000')
                            setRepaymentModalOpen(true)
                          }}
                          className="flex-1 py-2 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-700 text-xs font-bold hover:bg-emerald-100 transition-colors"
                        >
                          💵 Enregistrer Remboursement
                        </Button>
                        <Button
                          onClick={() => {
                            setWhatsappReminderAccount(acc)
                            setWhatsappReminderModalOpen(true)
                          }}
                          className="flex-1 py-2 rounded-xl bg-emerald-600 text-white text-xs font-bold hover:bg-emerald-700 transition-colors flex items-center justify-center gap-1 shadow-xs"
                        >
                          <Send size={13} />
                          <span>Relancer WhatsApp</span>
                        </Button>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          </Dialog>
        )}

        {/* Modal Sub-component: Remboursement de dette */}
        {repaymentModalOpen && repaymentAccount && (
          <div
            className="absolute inset-0 z-50 flex items-center justify-center px-4"
            style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(2px)' }}
            onClick={() => setRepaymentModalOpen(false)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Remboursement de dette</h3>
                  <p className="text-xs text-blue-600 font-medium">Client : {repaymentAccount.name}</p>
                </div>
                <Button onClick={() => setRepaymentModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Montant remboursé (FCFA)</label>
                <Input
                  type="number"
                  value={repaymentAmountInput}
                  onChange={(e) => setRepaymentAmountInput(e.target.value)}
                  className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-base font-bold text-gray-900 outline-none"
                  placeholder="Ex: 2000"
                  autoFocus
                />
              </div>

              <Button
                disabled={!repaymentAmountInput || Number(repaymentAmountInput) <= 0}
                onClick={() => {
                  const amt = Number(repaymentAmountInput)
                  const newMvt: CreditMovement = {
                    id: `mvt-${Date.now()}`,
                    date: "Aujourd'hui",
                    type: 'repayment',
                    amount: amt,
                    description: 'Remboursement en caisse',
                  }
                  setCreditAccounts((prev) =>
                    prev.map((acc) =>
                      acc.id === repaymentAccount.id
                        ? { ...acc, movements: [...acc.movements, newMvt] }
                        : acc
                    )
                  )
                  setRepaymentModalOpen(false)
                  showToast(`Remboursement de ${amt.toLocaleString('fr-FR')} FCFA enregistré pour ${repaymentAccount.name} !`)
                }}
                className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-emerald-600 active:scale-95 transition-transform shadow-md"
              >
                Valider le remboursement
              </Button>
            </div>
          </div>
        )}

        {/* Modal Sub-component: Relance WhatsApp Simulation */}
        {whatsappReminderModalOpen && whatsappReminderAccount && (
          <div
            className="absolute inset-0 z-50 flex items-center justify-center px-4"
            style={{ backgroundColor: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(2px)' }}
            onClick={() => setWhatsappReminderModalOpen(false)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl animate-in zoom-in-95 duration-200"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div className="flex items-center gap-2">
                  <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-600 flex items-center justify-center">
                    <Send size={16} />
                  </div>
                  <div>
                    <h3 className="font-bold text-gray-900 text-sm">Relance WhatsApp</h3>
                    <p className="text-[11px] text-gray-500">{whatsappReminderAccount.name} ({whatsappReminderAccount.phone || 'Sans num.'})</p>
                  </div>
                </div>
                <Button onClick={() => setWhatsappReminderModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              <div className="p-3.5 bg-emerald-50/60 border border-emerald-200/60 rounded-2xl space-y-2 text-xs font-mono text-emerald-950">
                <p className="font-bold text-[10px] uppercase text-emerald-700 font-sans tracking-wide">Aperçu du message envoyé :</p>
                <p className="leading-relaxed">
                  Bonjour <strong>{whatsappReminderAccount.name}</strong>, rappel amical de votre boutique <strong>{shopName}</strong> : votre solde impayé s'élève actuellement à <strong>{getAccountBalance(whatsappReminderAccount).toLocaleString('fr-FR')} FCFA</strong>.
                  <br /><br />
                  Merci d'effectuer votre règlement en boutique ou par Mobile Money. À très bientôt !
                </p>
              </div>

              <Button
                onClick={() => {
                  setWhatsappReminderModalOpen(false)
                  showToast(`Relance WhatsApp envoyée à ${whatsappReminderAccount.name} !`)
                }}
                className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-emerald-600 active:scale-95 transition-transform shadow-md flex items-center justify-center gap-2"
              >
                <Send size={16} />
                <span>Simuler l'envoi WhatsApp</span>
              </Button>
            </div>
          </div>
        )}

        {/* ── MODAL: ENRICHED CLIENT PWA EXPERIENCE (MOBILE MONEY USSD + 4 TABS + HYBRID TRANSPORT) ── */}
        {clientPwaModalOpen && (
          <Dialog className={`lk-client-pwa lk-client-pwa--${clientPwaTheme} absolute inset-0 z-50 flex flex-col bg-slate-900 text-white overflow-y-auto animate-in slide-in-from-bottom duration-200`} label="Espace client" onDismiss={() => setClientPwaModalOpen(false)}>
            {/* Identité de la boutique et contrôles propres à l'expérience client. */}
            <div className="flex items-center justify-between px-4 py-3 border-b border-slate-800 flex-shrink-0 sticky top-0 bg-slate-900 z-10">
              <div className="flex min-w-0 items-center gap-2">
                <ShopAvatar shop={{ id: clientPwaActiveShop?.id ?? 'shop-active', name: clientPwaActiveShop?.name ?? shopName, city: clientPwaActiveShop?.city ?? shopCity, image: null }} size={32} />
                <div className="min-w-0">
                  <h2 className="truncate text-xs font-bold text-white">{clientPwaActiveShop?.name ?? shopName}</h2>
                  <p className="truncate text-[10px] text-purple-300">Catalogue client · {clientPwaActiveShop?.city ?? shopCity}</p>
                </div>
              </div>
              <div className="flex shrink-0 items-center gap-1">
                <Button
                  onClick={() => setClientPwaThemePreference(clientPwaTheme === 'dark' ? 'light' : 'dark')}
                  className="flex h-8 w-8 items-center justify-center rounded-xl bg-slate-800 text-slate-300 hover:text-white"
                  title={clientPwaTheme === 'dark' ? 'Passer au thème clair du catalogue client' : 'Passer au thème sombre du catalogue client'}
                >
                  {clientPwaTheme === 'dark' ? <Sun size={15} /> : <Moon size={15} />}
                </Button>
                <Button
                  onClick={() => setClientPwaAboutOpen((open) => !open)}
                  className="flex h-8 w-8 items-center justify-center rounded-xl bg-slate-800 text-slate-300 hover:text-white"
                  title="À propos de Lynkstor Client"
                  aria-expanded={clientPwaAboutOpen}
                >
                  <Info size={15} />
                </Button>
                {/* État de démonstration : ne représente pas un transport confirmé. */}
                <Button
                  onClick={() => {
                    const nextMode = clientPwaTransportMode === 'cloud' ? 'catalogue_local' : 'cloud'
                    setClientPwaTransportMode(nextMode)
                    showToast(nextMode === 'cloud' ? "Démo PWA : état Cloud affiché" : "Démo PWA : état Wi-Fi local affiché")
                  }}
                  className={`px-2 py-1 rounded-xl text-[10px] font-bold border flex items-center gap-1 cursor-pointer transition-all ${clientPwaTransportMode === 'cloud'
                    ? 'bg-emerald-950/80 text-emerald-300 border-emerald-500/50 hover:bg-emerald-900/80'
                    : 'bg-amber-950/80 text-amber-300 border-amber-500/50 hover:bg-amber-900/80'
                    }`}
                  title="Changer l’état de connectivité simulé du catalogue"
                >
                  {clientPwaTransportMode === 'cloud' ? (
                    <>
                      <Cloud size={12} className="text-emerald-400" />
                      <span>Cloud démo</span>
                    </>
                  ) : (
                    <>
                      <Wifi size={12} className="text-amber-400" />
                      <span>Wi-Fi démo</span>
                    </>
                  )}
                </Button>
                <Button
                  onClick={() => {
                    setClientPwaModalOpen(false)
                    setClientPwaStep('catalog')
                  }}
                  className="p-1.5 rounded-xl bg-slate-800 text-slate-400 hover:text-white" aria-label="Fermer"
                >
                  <X size={18} />
                </Button>
              </div>
            </div>

            {clientPwaAboutOpen && (
              <div className="border-b border-slate-800 bg-slate-950 px-4 py-2 text-[11px] text-slate-300" role="status">
                <strong className="text-white">Lynkstor Client</strong> permet de consulter ce catalogue et de préparer une commande. Les paiements et la synchronisation affichés ici restent des démonstrations tant qu’un service n’est pas connecté.
              </div>
            )}

            {/* PWA 4-Tab Navigation Bar */}
            <div className="grid grid-cols-4 bg-slate-950 px-2 py-1.5 border-b border-slate-800 flex-shrink-0 text-xs font-bold gap-1 sticky top-[53px] z-10" role="tablist" aria-label="Navigation de l'espace client">
              <Button
                onClick={() => {
                  setClientPwaTab('catalog')
                  setClientPwaStep('catalog')
                }}
                role="tab"
                aria-selected={clientPwaTab === 'catalog'}
                className={`min-w-0 py-1.5 rounded-xl text-[10px] font-bold transition-all flex items-center justify-center gap-1 ${clientPwaTab === 'catalog' && clientPwaStep !== 'checkout' && clientPwaStep !== 'ussd_push' && clientPwaStep !== 'confirmed'
                  ? 'bg-purple-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800'
                  }`}
              >
                <Package size={13} />
                <span>Catalogue</span>
              </Button>
              <Button
                onClick={() => setClientPwaTab('repertoire')}
                role="tab"
                aria-selected={clientPwaTab === 'repertoire'}
                aria-label="Mes boutiques"
                className={`min-w-0 py-1.5 rounded-xl text-[10px] font-bold transition-all flex items-center justify-center gap-1 ${clientPwaTab === 'repertoire' ? 'bg-purple-600 text-white shadow-sm' : 'text-slate-400 hover:text-white hover:bg-slate-800'
                  }`}
              >
                <Store size={13} />
                <span>Boutiques</span>
              </Button>
              <Button
                onClick={() => setClientPwaTab('historique')}
                role="tab"
                aria-selected={clientPwaTab === 'historique'}
                className={`min-w-0 py-1.5 rounded-xl text-[10px] font-bold transition-all flex items-center justify-center gap-1 relative ${clientPwaTab === 'historique' ? 'bg-purple-600 text-white shadow-sm' : 'text-slate-400 hover:text-white hover:bg-slate-800'
                  }`}
              >
                <FileText size={13} />
                <span>Historique</span>
                {clientPwaOrders.length > 0 && (
                  <span className="w-4 h-4 rounded-full bg-purple-400 text-slate-950 text-[9px] font-extrabold flex items-center justify-center">
                    {clientPwaOrders.length}
                  </span>
                )}
              </Button>
              <Button
                onClick={() => setClientPwaTab('autorisations')}
                role="tab"
                aria-selected={clientPwaTab === 'autorisations'}
                aria-label="Autorisations et confidentialité"
                className={`min-w-0 py-1.5 rounded-xl text-[10px] font-bold transition-all flex items-center justify-center gap-1 ${clientPwaTab === 'autorisations' ? 'bg-purple-600 text-white shadow-sm' : 'text-slate-400 hover:text-white hover:bg-slate-800'
                  }`}
              >
                <Lock size={13} />
                <span>Options</span>
              </Button>
            </div>

            {/* Transport Banner Warning if Wi-Fi Local */}
            {clientPwaTransportMode === 'catalogue_local' && (
              <div className="bg-amber-950/90 border-b border-amber-800/80 px-4 py-2 text-[11px] text-amber-200 flex items-center gap-2 animate-in fade-in">
                <Wifi size={15} className="text-amber-400 flex-shrink-0" />
                <p className="leading-tight">
                  <strong className="font-bold text-amber-300">Mode Wi-Fi Local (Sans Internet) :</strong> Catalogue servi depuis le boîtier commerçant sur le réseau Wi-Fi local du magasin (`192.168.4.1`). Seul le paiement en caisse est disponible.
                </p>
              </div>
            )}

            <div className="p-4 space-y-4 flex-1">
              {/* TAB 1: CATALOGUE */}
              {clientPwaTab === 'catalog' && clientPwaStep === 'catalog' && (
                <div className="space-y-3">
                  {/* Order Mode Selector: Scan & Achat vs Précommande */}
                  <div className="flex bg-slate-800 p-1 rounded-2xl border border-slate-700">
                    <Button
                      onClick={() => {
                        setClientPwaOrderMode('scan_achat')
                        showToast("Mode PWA : Scan & Achat en magasin")
                      }}
                      className={`flex-1 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-1.5 cursor-pointer ${clientPwaOrderMode === 'scan_achat' ? 'bg-purple-600 text-white shadow-xs' : 'text-slate-400 hover:text-slate-200'
                        }`}
                    >
                      <span>⚡ Scan & Achat (Magasin)</span>
                    </Button>
                    <Button
                      onClick={() => {
                        setClientPwaOrderMode('precommande')
                        showToast("Mode PWA : Précommande (Retrait / Click & Collect)")
                      }}
                      className={`flex-1 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-1.5 cursor-pointer ${clientPwaOrderMode === 'precommande' ? 'bg-purple-600 text-white shadow-xs' : 'text-slate-400 hover:text-slate-200'
                        }`}
                    >
                      <span>📦 Précommande (Retrait)</span>
                    </Button>
                  </div>

                  <div className="p-3 bg-purple-950/60 border border-purple-800/60 rounded-2xl text-xs flex items-center justify-between">
                    <div>
                      <p className="font-bold text-purple-300 flex items-center gap-1.5">
                        <span>📱 Catalogue QR Code</span>
                        <span className="text-[9px] bg-purple-500/40 text-purple-200 px-1.5 py-0.2 rounded-full font-bold">
                          {clientPwaOrderMode === 'scan_achat' ? 'Scan rayon' : 'À distance'}
                        </span>
                      </p>
                      <p className="text-purple-200 text-[11px] mt-0.5">
                        {clientPwaOrderMode === 'scan_achat'
                          ? 'Constituez votre panier au fur et à mesure dans les rayons.'
                          : 'Préparez votre commande et récupérez-la au comptoir.'}
                      </p>
                    </div>

                    {/* Camera Barcode Scanner Simulation Button */}
                    <Button
                      onClick={() => setClientPwaBarcodeScannerOpen(true)}
                      className="px-2.5 py-1.5 rounded-xl bg-purple-600 hover:bg-purple-700 text-white text-[10px] font-bold shadow-xs active:scale-95 transition-transform flex items-center gap-1 flex-shrink-0"
                      title="Scanner le code-barres d'un produit en rayon"
                    >
                      <Camera size={14} />
                      <span>Scanner rayon</span>
                    </Button>
                  </div>

                  <p className="text-xs font-bold text-slate-400 uppercase tracking-wide">Produits disponibles au catalogue ({publicCatalogueProducts.length})</p>
                  <div className={catalogueDisplay === 'grid' ? 'grid grid-cols-2 gap-2' : 'space-y-2'} aria-label={`Catalogue client en ${catalogueDisplay === 'grid' ? 'grille' : 'liste'}`}>
                    {publicCatalogueProducts.map((p) => (
                      <div key={p.id} className={`bg-slate-800/80 border border-slate-700/80 rounded-2xl p-3 flex ${catalogueDisplay === 'grid' ? 'flex-col justify-between space-y-2 min-h-[238px]' : 'items-center gap-3 min-h-[96px]'}`}>
                        <ProductThumbnail product={p} className={`${catalogueDisplay === 'grid' ? 'h-28 w-full' : 'h-16 w-16 shrink-0'} rounded-xl border border-slate-600 bg-slate-700`} />
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-2">
                            <p className="text-xs font-bold text-white truncate">{p.name}</p>
                            <ProductStockBadge product={p} publicView />
                          </div>
                          <p className="text-[10px] text-slate-400">{p.category}</p>
                          <p className="text-xs font-bold text-purple-400 mt-1">{p.price.toLocaleString('fr-FR')} FCFA</p>
                        </div>
                        <Button
                          onClick={() => {
                            const existing = clientPwaCart.find((item) => item.product.id === p.id)
                            if (existing && existing.qty >= p.stock) {
                              showToast(`Stock épuisé pour ${p.name}.`)
                              return
                            }
                            setClientPwaCart((prev) => {
                              const item = prev.find((entry) => entry.product.id === p.id)
                              if (item) {
                                return prev.map((entry) => (entry.product.id === p.id ? { ...entry, qty: entry.qty + 1 } : entry))
                              }
                              return [...prev, { product: p, qty: 1 }]
                            })
                            showToast(`Ajouté au panier client : ${p.name}`)
                          }}
                          className={`${catalogueDisplay === 'grid' ? 'h-9 w-9 self-end' : 'min-h-10 w-auto shrink-0 px-3'} py-1.5 rounded-xl bg-purple-600 hover:bg-purple-700 text-white font-bold text-[11px] transition-colors flex items-center justify-center gap-1 active:scale-95`}
                          aria-label={`Ajouter ${p.name} au panier`}
                        >
                          <ShoppingCart size={16} />
                          {catalogueDisplay === 'list' && <span>Ajouter</span>}
                        </Button>
                      </div>
                    ))}
                  </div>

                  {clientPwaCart.length > 0 && (
                    <div className="pt-2 sticky bottom-4">
                      <Button
                        onClick={() => setClientPwaStep('checkout')}
                        className="w-full py-3.5 rounded-2xl bg-gradient-to-r from-purple-600 to-indigo-600 text-white font-bold text-sm shadow-xl flex items-center justify-between px-4 cursor-pointer active:scale-98 transition-transform"
                      >
                        <span>Panier ({clientPwaCart.reduce((s, i) => s + i.qty, 0)} art.)</span>
                        <span>{clientPwaCart.reduce((s, i) => s + i.product.price * i.qty, 0).toLocaleString('fr-FR')} FCFA ➔</span>
                      </Button>
                    </div>
                  )}
                </div>
              )}

              {/* CHECKOUT STEP WITH PROGRESSIVE IDENTIFICATION & OPT-IN */}
              {clientPwaStep === 'checkout' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="flex items-center justify-between">
                    <Button
                      onClick={() => setClientPwaStep('catalog')}
                      className="text-xs text-purple-400 font-bold flex items-center gap-1"
                    >
                      <ChevronLeft size={16} />
                      <span>Retour au catalogue</span>
                    </Button>
                    <span className="text-[10px] font-bold text-slate-400">
                      Mode : {clientPwaOrderMode === 'scan_achat' ? 'Scan & Achat en magasin' : 'Précommande à distance'}
                    </span>
                  </div>

                  {/* Order Items Summary */}
                  <div className="p-4 bg-slate-800 border border-slate-700 rounded-2xl space-y-2 text-xs">
                    <p className="text-xs font-bold text-slate-300 uppercase tracking-wide">Résumé de la commande</p>
                    {clientPwaCart.map((i) => (
                      <div key={i.product.id} className="flex items-start gap-2.5 border-b border-slate-700/80 py-2 last:border-0">
                        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl border border-slate-600 bg-slate-900 p-1.5"><ProductThumbnail product={i.product} className="h-full w-full" /></div>
                        <div className="min-w-0 flex-1">
                          <p className="font-bold leading-4 text-white break-words">{i.product.name}</p>
                          <div className="mt-1 flex items-center gap-1.5 text-[10px] text-slate-400">
                            <ProductStockBadge product={i.product} publicView />
                            <span>{i.product.price.toLocaleString('fr-FR')} FCFA × {i.qty}</span>
                          </div>
                        </div>
                        <span className="shrink-0 pt-0.5 text-right font-bold text-white">{(i.product.price * i.qty).toLocaleString('fr-FR')} FCFA</span>
                      </div>
                    ))}
                    <div className="border-t border-slate-700 pt-2 flex justify-between font-bold text-sm text-purple-300">
                      <span>Total à régler :</span>
                      <span>{clientPwaCart.reduce((s, i) => s + i.product.price * i.qty, 0).toLocaleString('fr-FR')} FCFA</span>
                    </div>
                  </div>

                  {/* Progressive Customer Identification Form */}
                  <div className="p-4 bg-slate-800 border border-purple-800/60 rounded-2xl space-y-3">
                    <div className="flex items-center justify-between">
                      <p className="text-xs font-bold text-purple-300 uppercase tracking-wide">Coordonnées du client (Fidélisation PWA)</p>
                      <span className="text-[9px] bg-purple-900 text-purple-300 px-1.5 py-0.5 rounded-full font-bold">Mémoire progressive</span>
                    </div>

                    <div className="space-y-1">
                      <label className="text-[11px] font-bold text-slate-300">Votre Nom / Pseudo <span className="text-red-400">*</span></label>
                      <Input
                        type="text"
                        value={clientPwaCustomerName}
                        onChange={(e) => setClientPwaCustomerName(e.target.value)}
                        placeholder="Ex: Jean Marc"
                        className="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white outline-none focus:border-purple-500"
                      />
                    </div>

                    <div className="space-y-1">
                      <label className="text-[11px] font-bold text-slate-300">Téléphone Mobile Money <span className="text-slate-400 font-normal">(Optionnel)</span></label>
                      <Input
                        type="tel"
                        value={clientPwaCustomerPhone}
                        onChange={(e) => setClientPwaCustomerPhone(e.target.value)}
                        placeholder="Ex: 699112233"
                        className="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-xs text-white outline-none focus:border-purple-500"
                      />
                    </div>

                    {/* Mandatory Non-Prechecked Opt-In Consent Checkbox */}
                    <label className="flex items-start gap-2.5 pt-1 cursor-pointer">
                      <Input
                        type="checkbox"
                        checked={clientPwaConsentOptIn}
                        onChange={(e) => setClientPwaConsentOptIn(e.target.checked)}
                        className="mt-0.5 rounded text-purple-600 focus:ring-purple-500"
                      />
                      <span className="text-[11px] text-slate-300 leading-tight">
                        J'accepte de recevoir des offres, promotions et tickets de caisse numériques de <strong className="text-white">{shopName}</strong> (Consentement modifiable à tout moment).
                      </span>
                    </label>
                  </div>

                  {/* Payment Method Selector */}
                  <div className="space-y-2">
                    <p className="text-xs font-bold text-slate-400 uppercase tracking-wide">Mode de règlement</p>

                    {clientPwaTransportMode === 'cloud' ? (
                      <Button
                        onClick={() => setClientPwaPayMethod('ussd')}
                        className={`w-full p-3.5 rounded-2xl border-2 transition-all flex items-center justify-between text-left cursor-pointer ${clientPwaPayMethod === 'ussd' ? 'border-purple-500 bg-purple-950/40 text-white' : 'border-slate-800 bg-slate-800 text-slate-400'
                          }`}
                      >
                        <div className="flex items-center gap-3">
                          <Smartphone size={20} className="text-purple-400" />
                          <div>
                            <p className="text-xs font-bold text-white">Demande USSD Mobile Money (démo)</p>
                            <p className="text-[10px] text-slate-400">Orange Money / MTN MoMo — en attente de la confirmation du prestataire</p>
                          </div>
                        </div>
                        {clientPwaPayMethod === 'ussd' && <CheckCircle size={18} className="text-purple-400" />}
                      </Button>
                    ) : (
                      <div className="p-3 bg-amber-950/60 border border-amber-800/80 rounded-2xl text-[11px] text-amber-200">
                        ⚠️ <strong>Paiement USSD indisponible en Wi-Fi Local :</strong> Nécessite une connexion Internet active côté boutique.
                      </div>
                    )}

                    <Button
                      onClick={() => setClientPwaPayMethod('caisse')}
                      className={`w-full p-3.5 rounded-2xl border-2 transition-all flex items-center justify-between text-left cursor-pointer ${clientPwaPayMethod === 'caisse' ? 'border-purple-500 bg-purple-950/40 text-white' : 'border-slate-800 bg-slate-800 text-slate-400'
                        }`}
                    >
                      <div className="flex items-center gap-3">
                        <Banknote size={20} className="text-slate-400" />
                        <div>
                          <p className="text-xs font-bold text-white">Payer en espèces à la caisse</p>
                          <p className="text-[10px] text-slate-400">Paiement sur place lors de la remise des articles</p>
                        </div>
                      </div>
                      {clientPwaPayMethod === 'caisse' && <CheckCircle size={18} className="text-purple-400" />}
                    </Button>
                  </div>

                  <Button
                    disabled={!clientPwaCustomerName.trim()}
                    onClick={() => {
                      if (clientPwaPayMethod === 'ussd' && clientPwaTransportMode === 'cloud') {
                        setClientPwaStep('ussd_push')
                      } else {
                        queueClientPwaOrder('non_requis', 'Espèces à la caisse')
                        showToast(clientPwaTransportMode === 'catalogue_local' ? 'Commande gardée localement, à synchroniser.' : 'Commande transmise à la file commerçant !')
                        setClientPwaStep('confirmed')
                      }
                    }}
                    className="w-full py-4 rounded-2xl bg-purple-600 hover:bg-purple-700 text-white font-bold text-sm shadow-xl transition-all disabled:opacity-40 cursor-pointer"
                  >
                    {clientPwaPayMethod === 'ussd' && clientPwaTransportMode === 'cloud'
                        ? 'Simuler une demande USSD (Mobile Money)'
                      : 'Envoyer la commande à la caisse'}
                  </Button>
                </div>
              )}

              {/* USSD PIN STEP */}
              {clientPwaStep === 'ussd_push' && (
                <div className="space-y-4 py-8 animate-in zoom-in-95 duration-200">
                  <div className="bg-slate-800 border border-purple-500/80 rounded-3xl p-5 space-y-4 shadow-2xl text-center">
                    <div className="w-12 h-12 rounded-full bg-orange-500 text-white font-bold text-lg flex items-center justify-center mx-auto shadow-md">
                      USSD
                    </div>
                    <div>
                      <h3 className="font-bold text-white text-base">Demande Orange Money / MTN MoMo</h3>
                      <p className="text-xs text-slate-300 mt-1">
                        Demande de paiement de <strong>{clientPwaCart.reduce((s, i) => s + i.product.price * i.qty, 0).toLocaleString('fr-FR')} FCFA</strong> pour <strong>{shopName}</strong> ({clientPwaCustomerName}).
                      </p>
                    </div>

                    <div className="space-y-1">
                      <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wide">Code PIN (Simulé : 4 chiffres)</label>
                      <Input
                        type="password"
                        maxLength={4}
                        value={clientPwaPin}
                        onChange={(e) => setClientPwaPin(e.target.value)}
                        placeholder="••••"
                        className="w-32 bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-center text-xl font-bold tracking-widest text-white outline-none mx-auto block"
                        autoFocus
                      />
                    </div>

                    <Button
                      disabled={clientPwaPin.length < 4}
                      onClick={() => {
                        queueClientPwaOrder('en_attente', 'Demande USSD (simulation)')
                        setClientPwaStep('confirmed')
                        showToast("Demande USSD simulée : le paiement reste à confirmer par le service.")
                      }}
                      className="w-full py-3.5 rounded-2xl bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-sm transition-all disabled:opacity-40 shadow-md cursor-pointer"
                    >
                      Simuler la réponse USSD
                    </Button>
                  </div>
                </div>
              )}

              {/* POST-ORDER CONFIRMATION & A2HS INSTALL PROMPT */}
              {clientPwaStep === 'confirmed' && (
                <div className="text-center py-6 space-y-4 animate-in zoom-in-95 duration-200">
                  <div className={`w-16 h-16 rounded-full flex items-center justify-center mx-auto ${clientPwaPayMethod === 'ussd' ? 'bg-amber-500/20 text-amber-400' : 'bg-emerald-500/20 text-emerald-400'}`}>
                    <CheckCircle size={40} />
                  </div>
                  <div>
                    <h3 className="text-lg font-bold text-white">{clientPwaPayMethod === 'ussd' ? 'Demande de paiement à confirmer' : 'Commande transmise'}</h3>
                    <p className="text-xs text-slate-300 mt-1">
                      {clientPwaPayMethod === 'ussd'
                        ? 'Paiement en attente : aucune confirmation externe n’a été reçue dans cette démonstration.'
                        : 'Paiement à effectuer à la caisse lors du retrait.'}
                    </p>
                  </div>

                  {/* A2HS PWA Installation Prompt Banner */}
                  <div className="bg-gradient-to-r from-purple-950 to-indigo-950 border border-purple-500/50 rounded-2xl p-4 text-left space-y-2 shadow-xl">
                    <div className="flex items-center gap-2">
                      <Smartphone className="text-purple-400 flex-shrink-0" size={20} />
                      <div>
                        <h4 className="text-xs font-bold text-white">📱 Installer Lynkstor Client</h4>
                        <p className="text-[10px] text-purple-200">L’installation doit être confirmée par votre navigateur ; elle n’est pas réalisée par cette démonstration.</p>
                      </div>
                    </div>
                    <Button
                      onClick={() => {
                        showToast("Démo : le navigateur doit confirmer l’installation de Lynkstor Client.")
                      }}
                      className="w-full py-2 rounded-xl bg-purple-600 hover:bg-purple-700 text-white font-bold text-xs shadow-xs active:scale-95 transition-all"
                    >
                      Voir l’instruction d’installation
                    </Button>
                  </div>

                  <div className="flex gap-2">
                    <Button
                      onClick={() => setClientPwaTab('historique')}
                      className="flex-1 py-3 px-4 rounded-xl bg-slate-800 text-purple-300 border border-slate-700 text-xs font-bold hover:bg-slate-700"
                    >
                      Voir mon ticket 📜
                    </Button>
                    <Button
                      onClick={() => {
                        setClientPwaStep('catalog')
                        setClientPwaCart([])
                        setClientPwaPin('')
                      }}
                      className="flex-1 py-3 px-4 rounded-xl bg-purple-600 text-white text-xs font-bold hover:bg-purple-700"
                    >
                      Nouvelle commande
                    </Button>
                  </div>
                </div>
              )}

              {/* TAB 2: MES BOUTIQUES (RÉPERTOIRE MULTI-BOUTIQUES) */}
              {clientPwaTab === 'repertoire' && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div className="p-3 bg-purple-950/60 border border-purple-800/60 rounded-2xl text-xs space-y-1">
                    <p className="font-bold text-purple-300">🏪 Répertoire de vos boutiques partenaires</p>
                    <p className="text-purple-200 text-[11px]">
                      Vos commerces visités (Mémoire progressive Palier 1/2/3). Accédez aux catalogues sans rescanner de QR Code.
                    </p>
                  </div>

                  <div className="space-y-2">
                    {clientPwaVisitedShops.map((shop) => (
                      <div
                        key={shop.id}
                        className={`p-3.5 rounded-2xl border transition-all space-y-2.5 ${shop.active ? 'bg-slate-800 border-purple-500/80 shadow-md' : 'bg-slate-800/60 border-slate-700'
                          }`}
                      >
                        <div className="flex items-start justify-between">
                          <div className="flex min-w-0 items-start gap-2">
                            <ShopAvatar shop={{ id: shop.id, name: shop.name, city: shop.city, image: null }} size={32} />
                            <div className="min-w-0">
                            <div className="flex items-center gap-2">
                              <h3 className="text-sm font-bold text-white">{shop.name}</h3>
                              {shop.active && (
                                <span className="text-[9px] font-bold bg-purple-900 text-purple-300 border border-purple-700 px-1.5 py-0.2 rounded-full">
                                  Boutique actuelle
                                </span>
                              )}
                            </div>
                            <p className="text-[10px] text-slate-400 mt-0.5">
                              📍 {shop.city} · Sector : {shop.sector} · Visite : {shop.lastVisit}
                            </p>
                            </div>
                          </div>
                          <div className="flex shrink-0 items-center gap-1">
                            <span className="text-xs font-extrabold text-amber-400 bg-amber-950/80 border border-amber-800/80 px-2 py-0.5 rounded-full">
                              ⭐ {shop.points} Pts
                            </span>
                            {!shop.active && (
                              <Button
                                onClick={() => setClientPwaVisitedShops((shops) => shops.filter((item) => item.id !== shop.id))}
                                className="flex h-8 w-8 items-center justify-center rounded-lg text-slate-400 hover:bg-slate-700 hover:text-white"
                                title={`Retirer ${shop.name} des boutiques visitées`}
                              >
                                <Trash2 size={14} />
                              </Button>
                            )}
                          </div>
                        </div>

                        {/* Discrete Promotion Banner */}
                        {shop.promo && (
                          <div className="bg-purple-950/80 border border-purple-800/80 p-2 rounded-xl text-[11px] text-purple-200 flex items-center justify-between">
                            <span className="font-medium">🏷️ {shop.promo}</span>
                            <span className="text-[9px] font-bold text-purple-300 bg-purple-900 px-1.5 py-0.5 rounded-full">Offre active</span>
                          </div>
                        )}

                        <Button
                          onClick={() => {
                            if (!shop.active) {
                              setClientPwaCart([])
                              showToast(`Le catalogue de ${shop.name} nécessite sa source de données ; aucun article de ${shopName} n’a été conservé.`)
                              return
                            }
                            setClientPwaTab('catalog')
                            setClientPwaStep('catalog')
                            showToast(`Catalogue ${shop.name} ouvert.`)
                          }}
                          className="w-full py-2 rounded-xl bg-purple-600/80 hover:bg-purple-600 text-white font-bold text-xs flex items-center justify-center gap-1 transition-colors"
                        >
                          <span>{shop.active ? 'Ouvrir le catalogue' : 'Catalogue à connecter'}</span>
                          <ChevronRight size={14} />
                        </Button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* TAB 3: MON HISTORIQUE & TICKETS NUMÉRIQUES */}
              {clientPwaTab === 'historique' && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div className="p-3 bg-purple-950/60 border border-purple-800/60 rounded-2xl text-xs space-y-1">
                    <p className="font-bold text-purple-300">📜 Historique des commandes & Tickets numériques</p>
                    <p className="text-purple-200 text-[11px]">
                      Retrouvez vos achats passés, le suivi en direct et vos reçus dématérialisés.
                    </p>
                  </div>

                  <div className="space-y-2.5">
                    {clientPwaOrders.length === 0 ? (
                      <div className="rounded-2xl border border-slate-700 bg-slate-800 p-5 text-center text-xs text-slate-300">
                        Vous n’avez pas encore de commande dans cette boutique. Votre premier ticket apparaîtra ici après transmission.
                      </div>
                    ) : clientPwaOrders.map((ord) => (
                      <div key={ord.id} className="bg-slate-800 border border-slate-700 rounded-2xl p-3.5 space-y-3">
                        <div className="flex items-center justify-between border-b border-slate-700/80 pb-2">
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-bold text-white">{ord.id}</span>
                              <span className="text-[10px] text-slate-400">· {ord.date}</span>
                            </div>
                            <p className="text-xs font-semibold text-purple-300 mt-0.5">{ord.shopName}</p>
                          </div>
                          <div className="text-right">
                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${ord.status === 'Nouvelle'
                              ? 'bg-amber-950 text-amber-300 border-amber-800'
                              : 'bg-slate-700 text-slate-200 border-slate-600'}`}>
                              {ord.status}
                            </span>
                            <p className="text-xs font-bold text-white mt-1">{ord.total.toLocaleString('fr-FR')} FCFA</p>
                          </div>
                        </div>

                        {/* Digital Receipt Breakdown */}
                        <div className="bg-slate-900/80 rounded-xl p-2.5 space-y-1.5 text-xs">
                          <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wide">Ticket numérique</p>
                          {ord.items.map((it, idx) => (
                            <div key={idx} className="flex justify-between items-center text-slate-300">
                              <span>{it.name} × {it.qty}</span>
                              <span className="font-bold text-white">{(it.price * it.qty).toLocaleString('fr-FR')} FCFA</span>
                            </div>
                          ))}
                          <div className="border-t border-slate-800 pt-1 flex justify-between items-center text-[11px] text-slate-400">
                            <span>Règlement :</span>
                            <span className={`font-bold ${ord.payStatus === 'en_attente' ? 'text-amber-400' : 'text-slate-300'}`}>{ord.payMethod} ({ord.payStatus})</span>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* TAB 4: MES AUTORISATIONS & CONFIDENTIALITÉ */}
              {clientPwaTab === 'autorisations' && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div className="p-3 bg-purple-950/60 border border-purple-800/60 rounded-2xl text-xs space-y-1">
                    <p className="font-bold text-purple-300">🔒 Gestion des autorisations & Vie privée</p>
                    <p className="text-purple-200 text-[11px]">
                      Contrôle granulaire par boutique. Vous pouvez accorder ou retirer votre consentement d'envoi d'offres à tout moment.
                    </p>
                  </div>

                  <div className="space-y-2">
                    {clientPwaVisitedShops.map((shop) => {
                      const isAllowed = clientPwaConsents[shop.id] ?? true
                      return (
                        <div key={shop.id} className="bg-slate-800 border border-slate-700 rounded-2xl p-3.5 flex items-center justify-between">
                          <div>
                            <h4 className="text-xs font-bold text-white">{shop.name}</h4>
                            <p className="text-[10px] text-slate-400 mt-0.5">Offres WhatsApp, SMS & Notifications Push</p>
                          </div>
                          <Button
                            onClick={() => {
                              const nextState = !isAllowed
                              setClientPwaConsents((prev) => ({ ...prev, [shop.id]: nextState }))
                              showToast(nextState ? `Autorisations activées pour ${shop.name}` : `Autorisations retirées pour ${shop.name}`)
                            }}
                            role="switch"
                            aria-checked={isAllowed}
                            aria-label={`Offres et notifications de ${shop.name}`}
                            className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer ${isAllowed
                              ? 'bg-emerald-600 text-white shadow-xs'
                              : 'bg-slate-700 text-slate-400'
                              }`}
                          >
                            {isAllowed ? 'Autorisé ON' : 'Bloqué OFF'}
                          </Button>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )}
            </div>

            {/* Simulated Barcode Scanner Camera Overlay */}
            {clientPwaBarcodeScannerOpen && (
              <div className="absolute inset-0 z-50 bg-black/90 flex flex-col items-center justify-center p-6 space-y-4 animate-in fade-in">
                <div className="relative w-64 h-64 border-2 border-purple-500 rounded-3xl overflow-hidden flex items-center justify-center bg-slate-900/50">
                  <div className="absolute inset-x-0 top-0 h-1 bg-purple-400 animate-bounce shadow-lg" />
                  <Camera size={48} className="text-purple-400 animate-pulse" />
                  <p className="absolute bottom-4 text-[10px] font-bold text-purple-200 bg-black/60 px-3 py-1 rounded-full">
                    Placez le code-barres du rayon ici
                  </p>
                </div>
                <div className="text-center space-y-1">
                  <h3 className="text-sm font-bold text-white">Scan produit en rayon (Simulation)</h3>
                  <p className="text-xs text-slate-400">Scanner la boîte ou le produit physiquement dans la boutique</p>
                </div>
                <div className="flex gap-3 w-full max-w-xs">
                  <Button
                    onClick={() => {
                      const randomProd = publicCatalogueProducts[Math.floor(Math.random() * publicCatalogueProducts.length)]
                      if (!randomProd) {
                        showToast('Aucun produit disponible à scanner pour le moment.')
                        return
                      }
                      setClientPwaCart((prev) => {
                        const existing = prev.find((i) => i.product.id === randomProd.id)
                        if (existing) {
                          return prev.map((i) => (i.product.id === randomProd.id ? { ...i, qty: i.qty + 1 } : i))
                        }
                        return [...prev, { product: randomProd, qty: 1 }]
                      })
                      showToast(`Code-barres scanné : ${randomProd.name} ajouté !`)
                      setClientPwaBarcodeScannerOpen(false)
                    }}
                    className="flex-1 py-3 rounded-2xl bg-purple-600 hover:bg-purple-700 text-white font-bold text-xs"
                  >
                    Simuler Scan Réussi ⚡
                  </Button>
                  <Button
                    onClick={() => setClientPwaBarcodeScannerOpen(false)}
                    className="px-4 py-3 rounded-2xl bg-slate-800 text-slate-300 font-bold text-xs"
                  >
                    Fermer
                  </Button>
                </div>
              </div>
            )}
          </Dialog>
        )}

        {/* ── MODAL: GRILLE DES 4 FORFAITS D'ABONNEMENT ── */}
        {subscriptionPlansModalOpen && (
          <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200">
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => setSubscriptionPlansModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Forfaits & Tarification</h2>
                <p className="text-[11px] text-blue-600 font-medium">Offre actuelle : {enterpriseInfo.subscriptionPlan}</p>
              </div>
              <Button
                onClick={() => setSubscriptionPlansModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            <div className="p-4 space-y-4 flex-1">
              <div className="p-3 bg-blue-50/70 border border-blue-100 rounded-2xl text-xs text-blue-900">
                <p className="font-bold">✨ Évoluez au rythme de votre commerce</p>
                <p className="text-[11px] mt-0.5 text-blue-800">Commencez gratuitement et activez les modules avancés selon vos besoins.</p>
              </div>

              {/* 4 Plan Cards */}
              <div className="space-y-3">
                {[
                  {
                    name: 'Gratuit',
                    price: '0 FCFA',
                    period: 'pour toujours',
                    tag: 'Inclus',
                    features: ['Vente Hybride & Caisse', 'Stock Express & OCR Facture', 'Sync P2P Local & Cloud', 'Catalogue QR Code'],
                    active: enterpriseInfo.subscriptionPlan === 'Gratuit',
                  },
                  {
                    name: 'Essential',
                    price: '5 000 FCFA',
                    period: '/ mois',
                    tag: 'Recommandé Supérettes',
                    features: ['Toutes les fonctionnalités Gratuit', 'Sauvegarde Cloud continue', 'Tableaux de bord & Rapports Z', 'Support prioritaire WhatsApp'],
                    active: false,
                  },
                  {
                    name: 'Lynkstor Pro',
                    price: '10 000 FCFA',
                    period: '/ mois',
                    tag: 'PME & Croissance',
                    features: ['Toutes les fonctionnalités Essential', 'Assistant IA & Détection Marges', 'Fidélisation Client & WhatsApp', 'Multi-utilisateurs & Rôles'],
                    active: enterpriseInfo.subscriptionPlan === 'Lynkstor Pro',
                  },
                  {
                    name: 'Entreprise Multi-boutiques',
                    price: '20 000 FCFA',
                    period: '/ mois',
                    tag: 'Multi-Boutiques & Groupe',
                    features: ['Toutes les fonctionnalités Pro', 'Espace Groupe Multi-boutiques', 'Réaffectation du personnel', 'Vue consolidée & Rapports Groupe'],
                    active: enterpriseInfo.subscriptionPlan === 'Entreprise Multi-boutiques',
                  },
                ].map((plan) => (
                  <div
                    key={plan.name}
                    className={`p-4 rounded-3xl border-2 transition-all space-y-3 ${plan.active ? 'border-blue-600 bg-blue-50/40 shadow-sm' : 'border-gray-100 bg-white'
                      }`}
                  >
                    <div className="flex items-start justify-between">
                      <div>
                        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-100 text-blue-700">
                          {plan.tag}
                        </span>
                        <h3 className="text-base font-bold text-gray-900 mt-1">{plan.name}</h3>
                      </div>
                      <div className="text-right">
                        <p className="text-base font-bold text-gray-900">{plan.price}</p>
                        <p className="text-[10px] text-gray-400 font-medium">{plan.period}</p>
                      </div>
                    </div>

                    <ul className="space-y-1.5 text-xs text-gray-600">
                      {plan.features.map((f) => (
                        <li key={f} className="flex items-center gap-1.5">
                          <Check size={14} className="text-emerald-600 flex-shrink-0" />
                          <span>{f}</span>
                        </li>
                      ))}
                    </ul>

                    <Button
                      onClick={() => {
                        setEnterpriseInfo((prev) => ({ ...prev, subscriptionPlan: plan.name as any }))
                        showToast(`Forfait "${plan.name}" activé avec succès !`)
                        setSubscriptionPlansModalOpen(false)
                      }}
                      className={`w-full py-2.5 rounded-2xl font-bold text-xs transition-all ${plan.active
                        ? 'bg-blue-600 text-white shadow-xs'
                        : 'bg-gray-100 text-gray-800 hover:bg-gray-200'
                        }`}
                    >
                      {plan.active ? 'Forfait actuel' : 'Activer ce forfait'}
                    </Button>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* ── MODAL: HUB FIDÉLISATION & PROMOTIONS ── */}
        {loyaltyPromotionsModalOpen && (
          <Dialog className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto animate-in slide-in-from-bottom duration-200" label="Fidélité et promotions" onDismiss={() => setLoyaltyPromotionsModalOpen(false)}>
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button
                onClick={() => setLoyaltyPromotionsModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors" aria-label="Retour"
              >
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Fidélisation & Promotions</h2>
                <p className="text-[11px] text-purple-600 font-medium">{customers.length} clients enregistrés · {coupons.filter(c => c.active).length} coupons actifs</p>
              </div>
              <Button
                onClick={() => setLoyaltyPromotionsModalOpen(false)}
                className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors text-gray-500" aria-label="Fermer"
              >
                <X size={18} />
              </Button>
            </div>

            {/* Navigation Tabs */}
            <div className="flex border-b border-gray-100 bg-gray-50/80 px-2 py-1 gap-1 flex-shrink-0">
              {[
                { id: 'customers', label: 'Clients', icon: Users },
                { id: 'coupons', label: 'Coupons', icon: Tag },
                { id: 'rules', label: 'Règles & Tarifs', icon: Sliders },
                { id: 'marketing', label: 'Relances WhatsApp', icon: Send },
              ].map((t) => {
                const Icon = t.icon
                const active = loyaltyTab === t.id
                return (
                  <Button
                    key={t.id}
                    onClick={() => setLoyaltyTab(t.id as any)}
                    className={`flex-1 py-2 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-1 ${active ? 'bg-purple-600 text-white shadow-xs' : 'text-gray-500 hover:bg-gray-100'
                      }`}
                  >
                    <Icon size={14} />
                    <span>{t.label}</span>
                  </Button>
                )
              })}
            </div>

            <div className="p-4 space-y-4 flex-1">
              {/* TAB 1: CLIENTS */}
              {loyaltyTab === 'customers' && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div className="p-3.5 bg-gradient-to-r from-purple-900 to-indigo-900 text-white rounded-2xl shadow-md flex items-center justify-between">
                    <div>
                      <p className="text-[10px] font-bold uppercase tracking-wider text-purple-200">Programme de fidélité active</p>
                      <p className="text-sm font-bold text-white mt-0.5">1 Point tous les {loyaltySettings.earnRateFcfaPerPoint.toLocaleString('fr-FR')} F dépense</p>
                      <p className="text-[11px] text-purple-300">100 Points = {(100 * loyaltySettings.redemptionValuePerPoint).toLocaleString('fr-FR')} FCFA de réduction</p>
                    </div>
                    <Gift size={28} className="text-purple-300 opacity-80" />
                  </div>

                  <div className="flex items-center justify-between">
                    <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Répertoire clients fidélisés</p>
                    <span className="text-[10px] font-bold text-purple-600 bg-purple-50 px-2 py-0.5 rounded-full">{customers.length} membres</span>
                  </div>

                  <div className="space-y-2.5">
                    {customers.map((c) => (
                      <div key={c.id} className="bg-white rounded-2xl p-3.5 border border-gray-100 space-y-2 shadow-xs">
                        <div className="flex items-start justify-between">
                          <div className="flex items-center gap-2.5">
                            <div className="w-10 h-10 rounded-xl bg-purple-50 border border-purple-100 flex items-center justify-center text-purple-700 font-bold text-sm">
                              {c.name.substring(0, 2).toUpperCase()}
                            </div>
                            <div>
                              <div className="flex items-center gap-1.5">
                                <h3 className="text-xs font-bold text-gray-900">{c.name}</h3>
                                <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded-full ${c.tier === 'VIP' ? 'bg-amber-100 text-amber-800 border border-amber-300' :
                                  c.tier === 'Or' ? 'bg-yellow-100 text-yellow-800' :
                                    c.tier === 'Argent' ? 'bg-slate-100 text-slate-700' : 'bg-orange-50 text-orange-700'
                                  }`}>
                                  {c.tier === 'VIP' ? '👑 VIP' : c.tier === 'Or' ? '🟡 Or' : c.tier === 'Argent' ? '⚪ Argent' : '🟤 Bronze'}
                                </span>
                              </div>
                              <p className="text-[11px] text-gray-400 mt-0.5">📞 +237 {c.phone} · Visité {c.lastVisitDate}</p>
                            </div>
                          </div>
                          <div className="text-right">
                            <p className="text-sm font-bold text-purple-700">{c.pointsBalance} <span className="text-[10px] font-medium text-gray-400">Pts</span></p>
                            <p className="text-[10px] text-gray-500 font-medium">={(c.pointsBalance * loyaltySettings.redemptionValuePerPoint).toLocaleString('fr-FR')} F économisables</p>
                          </div>
                        </div>

                        <div className="pt-2 border-t border-gray-100 flex items-center justify-between text-[11px]">
                          <span className="text-gray-500">Cumul d'achats : <strong>{c.totalSpent.toLocaleString('fr-FR')} FCFA</strong> ({c.visitCount} visites)</span>
                          <div className="flex gap-1">
                            <Button
                              onClick={() => {
                                setPointsAdjustCustomer(c)
                                setPointsAdjustAmount('50')
                                setPointsAdjustModalOpen(true)
                              }}
                              className="px-2 py-1 rounded-lg bg-purple-50 text-purple-700 font-bold hover:bg-purple-100"
                            >
                              ⚡ Ajuster Pts
                            </Button>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* TAB 2: COUPONS */}
              {loyaltyTab === 'coupons' && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Codes Promo & Remises Flash</p>
                    <Button
                      onClick={() => setCreateCouponModalOpen(true)}
                      className="px-3 py-1.5 rounded-xl bg-purple-600 text-white font-bold text-xs flex items-center gap-1 shadow-xs active:scale-95 transition-transform"
                    >
                      <Plus size={14} />
                      <span>Créer un Code Promo</span>
                    </Button>
                  </div>

                  <div className="space-y-2.5">
                    {coupons.map((coup) => (
                      <div key={coup.id} className="bg-white rounded-2xl p-4 border border-gray-100 space-y-2.5 shadow-xs">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-sm font-bold bg-purple-50 text-purple-800 border border-purple-200 px-3 py-1 rounded-xl tracking-wider">
                              {coup.code}
                            </span>
                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${coup.active ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-400'}`}>
                              {coup.active ? '✅ Actif' : '⏸ Inactif'}
                            </span>
                          </div>
                          <Button
                            onClick={() => {
                              setCoupons(prev => prev.map(c => c.id === coup.id ? { ...c, active: !c.active } : c))
                              showToast(`Code ${coup.code} ${!coup.active ? 'activé' : 'désactivé'} !`)
                            }}
                            className="text-gray-400 hover:text-purple-600"
                          >
                            {coup.active ? <ToggleRight size={28} className="text-purple-600" /> : <ToggleLeft size={28} />}
                          </Button>
                        </div>

                        <div className="text-xs text-gray-700 space-y-1">
                          <p className="font-bold text-gray-900">
                            {coup.discountType === 'percent' ? `-${coup.discountValue}% de réduction sur le panier` : `-${coup.discountValue.toLocaleString('fr-FR')} FCFA de déduction fixe`}
                          </p>
                          <p className="text-[11px] text-gray-400">Plafond min : {coup.minOrderAmount.toLocaleString('fr-FR')} FCFA · Utilisé {coup.usageCount} fois</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* TAB 3: RÈGLES COMMERÇANT (DYNAMIQUE) */}
              {loyaltyTab === 'rules' && (
                <div className="space-y-4 animate-in fade-in duration-150">
                  <div className="bg-purple-50/70 border border-purple-100 rounded-2xl p-4 space-y-2 text-xs text-purple-900">
                    <p className="font-bold flex items-center gap-1.5 text-sm">
                      <Sliders size={16} className="text-purple-700" />
                      Configuration Dynamique du Commerce
                    </p>
                    <p className="text-[11px] leading-relaxed">
                      Définissez vos propres règles de fidélité. Chaque propriétaire peut personnaliser le barème de points et la valeur de rachat.
                    </p>
                  </div>

                  <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-4 shadow-sm">
                    <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                      <div>
                        <p className="text-xs font-bold text-gray-900">Activer le programme de fidélité</p>
                        <p className="text-[10px] text-gray-400">Attribution automatique de points en caisse</p>
                      </div>
                      <Button
                        onClick={() => {
                          setLoyaltySettings(prev => ({ ...prev, loyaltyEnabled: !prev.loyaltyEnabled }))
                          showToast(`Programme de fidélité ${!loyaltySettings.loyaltyEnabled ? 'activé' : 'désactivé'} !`)
                        }}
                      >
                        {loyaltySettings.loyaltyEnabled ? <ToggleRight size={30} className="text-purple-600" /> : <ToggleLeft size={30} className="text-gray-400" />}
                      </Button>
                    </div>

                    <div>
                      <label className="text-xs font-bold text-gray-700">Taux d'attribution (Dépense en FCFA pour 1 Point)</label>
                      <div className="flex items-center gap-2 mt-1">
                        <Input
                          type="number"
                          value={loyaltySettings.earnRateFcfaPerPoint}
                          onChange={(e) => setLoyaltySettings(prev => ({ ...prev, earnRateFcfaPerPoint: Math.max(100, Number(e.target.value)) }))}
                          className="flex-1 bg-gray-100 rounded-xl px-3 py-2.5 text-sm font-bold text-gray-900 outline-none"
                        />
                        <span className="text-xs font-bold text-gray-500">FCFA = 1 Point</span>
                      </div>
                      <p className="text-[10px] text-gray-400 mt-1">Valeur par défaut conseillée : 1 000 FCFA</p>
                    </div>

                    <div>
                      <label className="text-xs font-bold text-gray-700">Valeur de rachat (Valeur en FCFA de 1 Point)</label>
                      <div className="flex items-center gap-2 mt-1">
                        <Input
                          type="number"
                          value={loyaltySettings.redemptionValuePerPoint}
                          onChange={(e) => setLoyaltySettings(prev => ({ ...prev, redemptionValuePerPoint: Math.max(1, Number(e.target.value)) }))}
                          className="flex-1 bg-gray-100 rounded-xl px-3 py-2.5 text-sm font-bold text-gray-900 outline-none"
                        />
                        <span className="text-xs font-bold text-gray-500">FCFA par Point</span>
                      </div>
                      <p className="text-[10px] text-gray-400 mt-1">Exemple : 10 FCFA par Point ➔ 100 Pts = 1 000 FCFA de remise</p>
                    </div>

                    <Button
                      onClick={() => showToast("Paramètres du barème de fidélité enregistrés avec succès !")}
                      className="w-full py-3 rounded-2xl text-white font-bold text-xs bg-purple-600 active:scale-95 transition-all shadow-md"
                    >
                      Enregistrer le barème dynamique
                    </Button>
                  </div>
                </div>
              )}

              {/* TAB 4: MARKETING & RELANCES WHATSAPP */}
              {loyaltyTab === 'marketing' && (
                <div className="space-y-3 animate-in fade-in duration-150">
                  <div className="p-3.5 bg-emerald-900 text-white rounded-2xl shadow-md space-y-1">
                    <div className="flex items-center gap-2">
                      <Send size={18} className="text-emerald-300" />
                      <p className="text-xs font-bold uppercase tracking-wider text-emerald-200">Campagnes Marketing WhatsApp</p>
                    </div>
                    <p className="text-xs text-emerald-100 leading-relaxed">
                      Re-engagez vos clients fidèles en leur envoyant une promotion exclusive par message direct.
                    </p>
                  </div>

                  <div className="space-y-2">
                    <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Cibles recommandées par l'IA</p>

                    <div className="bg-white rounded-2xl p-3.5 border border-gray-100 space-y-3 shadow-xs">
                      <div className="flex items-start justify-between">
                        <div>
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-50 text-amber-700">
                            Clients inactifs (&gt; 30 jours)
                          </span>
                          <h3 className="text-xs font-bold text-gray-900 mt-1">Offre spécial retour en magasin</h3>
                          <p className="text-[11px] text-gray-400 mt-0.5">1 client identifié : Mme Suzanne Belinga (Dernier achat il y a 35j)</p>
                        </div>
                      </div>
                      <Button
                        onClick={() => showToast("Campagne WhatsApp envoyée à Mme Suzanne Belinga avec le code BIENVENUE10 !")}
                        className="w-full py-2.5 rounded-xl bg-emerald-600 text-white text-xs font-bold hover:bg-emerald-700 transition-colors flex items-center justify-center gap-1.5 shadow-xs"
                      >
                        <Send size={14} />
                        <span>Envoyer le message WhatsApp (Code BIENVENUE10)</span>
                      </Button>
                    </div>

                    <div className="bg-white rounded-2xl p-3.5 border border-gray-100 space-y-3 shadow-xs">
                      <div className="flex items-start justify-between">
                        <div>
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-50 text-purple-700">
                            Clients VIP (Niveau Or & VIP)
                          </span>
                          <h3 className="text-xs font-bold text-gray-900 mt-1">Offre de remerciement VIP</h3>
                          <p className="text-[11px] text-gray-400 mt-0.5">2 clients identifiés : M. Paul Etoa & M. Jean Ndongo</p>
                        </div>
                      </div>
                      <Button
                        onClick={() => showToast("Campagne WhatsApp VIP envoyée avec le code VIP2000 !")}
                        className="w-full py-2.5 rounded-xl bg-purple-600 text-white text-xs font-bold hover:bg-purple-700 transition-colors flex items-center justify-center gap-1.5 shadow-xs"
                      >
                        <Send size={14} />
                        <span>Envoyer l'Offre VIP (Code VIP2000)</span>
                      </Button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </Dialog>
        )}

        {/* Modal sub-component: Créer un code promo */}
        {createCouponModalOpen && (
          <div
            className="absolute inset-0 z-50 flex items-center justify-center px-4 bg-black/50 backdrop-blur-xs animate-backdrop"
            onClick={() => setCreateCouponModalOpen(false)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl perspective-1000 animate-card-flip"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Nouveau Code Promo</h3>
                  <p className="text-xs text-purple-600 font-medium">Coupon de réduction personnalisé</p>
                </div>
                <Button onClick={() => setCreateCouponModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Code du coupon (ex: FLASH2026)</label>
                <Input
                  type="text"
                  value={newCouponCode}
                  onChange={(e) => setNewCouponCode(e.target.value.toUpperCase())}
                  placeholder="EX: PROMO10"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-sm font-bold text-gray-900 uppercase outline-none"
                  autoFocus
                />
              </div>

              <div className="grid grid-cols-2 gap-2">
                <Button
                  onClick={() => setNewCouponType('percent')}
                  className={`py-2.5 rounded-xl font-bold text-xs ${newCouponType === 'percent' ? 'bg-purple-600 text-white' : 'bg-gray-100 text-gray-700'}`}
                >
                  % Pourcentage
                </Button>
                <Button
                  onClick={() => setNewCouponType('fixed')}
                  className={`py-2.5 rounded-xl font-bold text-xs ${newCouponType === 'fixed' ? 'bg-purple-600 text-white' : 'bg-gray-100 text-gray-700'}`}
                >
                  Fixe (FCFA)
                </Button>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Valeur de la réduction ({newCouponType === 'percent' ? '%' : 'FCFA'})</label>
                <Input
                  type="number"
                  value={newCouponVal}
                  onChange={(e) => setNewCouponVal(e.target.value)}
                  placeholder={newCouponType === 'percent' ? 'Ex: 10' : 'Ex: 1000'}
                  className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-sm font-bold text-gray-900 outline-none"
                />
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Montant minimum de commande (FCFA)</label>
                <Input
                  type="number"
                  value={newCouponMinOrder}
                  onChange={(e) => setNewCouponMinOrder(e.target.value)}
                  placeholder="Ex: 5000"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-sm font-bold text-gray-900 outline-none"
                />
              </div>

              <Button
                disabled={!newCouponCode.trim() || !newCouponVal}
                onClick={() => {
                  const createdCoupon: PromotionCoupon = {
                    id: `coup-${Date.now()}`,
                    code: newCouponCode.trim(),
                    discountType: newCouponType,
                    discountValue: Number(newCouponVal),
                    minOrderAmount: Number(newCouponMinOrder || 5000),
                    active: true,
                    usageCount: 0,
                  }
                  setCoupons((prev) => [createdCoupon, ...prev])
                  setCreateCouponModalOpen(false)
                  setNewCouponCode('')
                  setNewCouponVal('')
                  showToast(`Code Promo "${createdCoupon.code}" créé avec succès !`)
                }}
                className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-purple-600 active:scale-95 transition-all disabled:opacity-40 shadow-md"
              >
                Créer et activer le Code Promo
              </Button>
            </div>
          </div>
        )}

        {/* Modal sub-component: Ajuster Points */}
        {pointsAdjustModalOpen && pointsAdjustCustomer && (
          <div
            className="absolute inset-0 z-50 flex items-center justify-center px-4 bg-black/50 backdrop-blur-xs animate-backdrop"
            onClick={() => setPointsAdjustModalOpen(false)}
          >
            <div
              className="w-full bg-white rounded-3xl p-5 space-y-4 shadow-2xl perspective-1000 animate-card-flip"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div>
                  <h3 className="font-bold text-gray-900 text-base">Ajustement du Solde Pts</h3>
                  <p className="text-xs text-purple-600 font-medium">Client : {pointsAdjustCustomer.name}</p>
                </div>
                <Button onClick={() => setPointsAdjustModalOpen(false)} className="p-1 rounded-lg text-gray-400 hover:bg-gray-100" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-700">Nombre de Points à ajouter / déduire</label>
                <Input
                  type="number"
                  value={pointsAdjustAmount}
                  onChange={(e) => setPointsAdjustAmount(e.target.value)}
                  placeholder="Ex: 50"
                  className="w-full mt-1 bg-gray-100 rounded-xl px-4 py-3 text-sm font-bold text-gray-900 outline-none"
                  autoFocus
                />
              </div>

              <div className="grid grid-cols-2 gap-2">
                <Button
                  onClick={() => setPointsAdjustType('add')}
                  className={`py-2.5 rounded-xl font-bold text-xs ${pointsAdjustType === 'add' ? 'bg-emerald-600 text-white' : 'bg-gray-100 text-gray-700'}`}
                >
                  + Ajouter Points
                </Button>
                <Button
                  onClick={() => setPointsAdjustType('sub')}
                  className={`py-2.5 rounded-xl font-bold text-xs ${pointsAdjustType === 'sub' ? 'bg-red-600 text-white' : 'bg-gray-100 text-gray-700'}`}
                >
                  - Déduire Points
                </Button>
              </div>

              <Button
                disabled={!pointsAdjustAmount || Number(pointsAdjustAmount) <= 0}
                onClick={() => {
                  const pts = Number(pointsAdjustAmount)
                  const delta = pointsAdjustType === 'add' ? pts : -pts
                  setCustomers((prev) =>
                    prev.map((c) =>
                      c.id === pointsAdjustCustomer.id
                        ? { ...c, pointsBalance: Math.max(0, c.pointsBalance + delta) }
                        : c
                    )
                  )
                  setPointsAdjustModalOpen(false)
                  showToast(`Solde de points de ${pointsAdjustCustomer.name} mis à jour (${delta > 0 ? '+' : ''}${delta} Pts) !`)
                }}
                className="w-full py-3.5 rounded-2xl text-white font-bold text-sm bg-purple-600 active:scale-95 transition-all shadow-md disabled:opacity-40"
              >
                Confirmer l'ajustement
              </Button>
            </div>
          </div>
        )}

        {/* ── MODAL: REÇU POST-VENTE (IMPRESSION & WHATSAPP) ── */}
        {postSaleReceiptModalOpen && lastCompletedSale && (
          <div className="absolute inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs animate-backdrop">
            <div className="w-full max-w-sm bg-white rounded-3xl p-5 space-y-4 shadow-2xl perspective-1000 animate-card-flip">
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <div className="flex items-center gap-2">
                  <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center font-bold">
                    <CheckCircle size={18} />
                  </div>
                  <div>
                    <h3 className="font-bold text-gray-900 text-sm">Vente Encaissée avec Succès</h3>
                    <p className="text-[10px] text-gray-400">Réf: {lastCompletedSale.id} · {lastCompletedSale.paymentMode}</p>
                  </div>
                </div>
                <Button onClick={() => setPostSaleReceiptModalOpen(false)} className="p-1 text-gray-400 hover:text-gray-600" aria-label="Fermer">
                  <X size={18} />
                </Button>
              </div>

              {/* Receipt Preview */}
              <div className="bg-slate-50 border border-slate-200/80 rounded-2xl p-3.5 space-y-2 text-xs">
                <div className="flex justify-between items-center border-b border-slate-200 pb-2">
                  <span className="font-bold text-gray-900">{shopName}</span>
                  <span className="text-[10px] text-gray-400">{shopCity}</span>
                </div>
                <div className="space-y-1">
                  {lastCompletedSale.items.map((it, idx) => (
                    <div key={idx} className="flex justify-between text-gray-700">
                      <span>{it.name} × {it.qty}</span>
                      <span className="font-bold">{(it.price * it.qty).toLocaleString('fr-FR')} FCFA</span>
                    </div>
                  ))}
                </div>
                <div className="border-t border-slate-200 pt-2 flex justify-between items-center text-sm font-bold text-gray-900">
                  <span>TOTAL :</span>
                  <span className="text-blue-600">{lastCompletedSale.total.toLocaleString('fr-FR')} FCFA</span>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="space-y-2">
                <Button
                  onClick={() => {
                    const text = `🧾 Reçu de caisse - ${shopName}\nRéf: ${lastCompletedSale.id}\nTotal: ${lastCompletedSale.total.toLocaleString('fr-FR')} FCFA\nMerci pour votre visite !`
                    window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, '_blank')
                    showToast('Reçu numérique généré pour WhatsApp !')
                  }}
                  className="w-full py-3 rounded-2xl bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs flex items-center justify-center gap-2 shadow-xs active:scale-95 transition-transform"
                >
                  <Send size={15} />
                  <span>Envoyer le reçu sur WhatsApp</span>
                </Button>

                <Button
                  onClick={() => {
                    showToast('🖨️ Ticket de caisse imprimé sur l\'imprimante Bluetooth !')
                    setPostSaleReceiptModalOpen(false)
                  }}
                  className="w-full py-3 rounded-2xl bg-slate-900 hover:bg-slate-800 text-white font-bold text-xs flex items-center justify-center gap-2 active:scale-95 transition-transform"
                >
                  <Printer size={15} />
                  <span>Imprimer le ticket thermique Bluetooth</span>
                </Button>

                <Button
                  onClick={() => setPostSaleReceiptModalOpen(false)}
                  className="w-full py-2.5 rounded-xl bg-gray-100 text-gray-600 font-bold text-xs hover:bg-gray-200"
                >
                  Fermer sans impression
                </Button>
              </div>
            </div>
          </div>
        )}

        {/* ── MODAL: COMMANDES FOURNISSEURS & WHATSAPP DIRECT ── */}
        {supplierOrderModalOpen && (
          <div className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto perspective-1000 animate-card-flip">
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button onClick={() => setSupplierOrderModalOpen(false)} className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200" aria-label="Retour">
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Réapprovisionnement Fournisseur</h2>
                <p className="text-[11px] text-blue-600 font-medium">Commande sortante · Secteur {sector}</p>
              </div>
              <Button onClick={() => setSupplierOrderModalOpen(false)} className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-500" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div className="p-4 space-y-4 flex-1">
              {/* Channel Selector */}
              <div className="flex bg-gray-100 p-1 rounded-2xl border border-gray-200/60">
                <Button
                  onClick={() => setSupplierOrderType('whatsapp_informal')}
                  className={`flex-1 py-2 rounded-xl text-xs font-bold transition-all ${supplierOrderType === 'whatsapp_informal' ? 'bg-white text-emerald-700 shadow-xs' : 'text-gray-500'}`}
                >
                  💬 Grossiste Informel (WhatsApp Direct)
                </Button>
                <Button
                  onClick={() => setSupplierOrderType('lynkstor_digital')}
                  className={`flex-1 py-2 rounded-xl text-xs font-bold transition-all ${supplierOrderType === 'lynkstor_digital' ? 'bg-white text-blue-600 shadow-xs' : 'text-gray-500'}`}
                >
                  ☁️ Fournisseur Lynkstor
                </Button>
              </div>

              {/* Form Info */}
              <div className="space-y-3 bg-gray-50 p-3.5 rounded-2xl border border-gray-100">
                <div>
                  <label className="text-xs font-bold text-gray-700">Grossiste / Fournisseur</label>
                  <Input
                    type="text"
                    value={supplierWholesalerName}
                    onChange={(e) => setSupplierWholesalerName(e.target.value)}
                    className="w-full mt-1 bg-white rounded-xl px-3 py-2 text-xs font-bold text-gray-900 outline-none border border-gray-200"
                  />
                </div>
                {supplierOrderType === 'whatsapp_informal' && (
                  <div>
                    <label className="text-xs font-bold text-gray-700">Numéro WhatsApp du Grossiste</label>
                    <Input
                      type="text"
                      value={supplierWholesalerPhone}
                      onChange={(e) => setSupplierWholesalerPhone(e.target.value)}
                      className="w-full mt-1 bg-white rounded-xl px-3 py-2 text-xs font-bold text-gray-900 outline-none border border-gray-200"
                    />
                  </div>
                )}
              </div>

              {/* Order Items */}
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Articles à commander</p>
                  <Button
                    onClick={() => {
                      const newId = String(Date.now())
                      setSupplierOrderItems((prev) => [...prev, { id: newId, name: 'Lait Concentré 1kg', qty: 12, price: 950 }])
                    }}
                    className="text-xs font-bold text-blue-600 hover:underline"
                  >
                    + Ajouter un article
                  </Button>
                </div>

                <div className="space-y-2">
                  {supplierOrderItems.map((item) => (
                    <div key={item.id} className="bg-white border border-gray-200 rounded-2xl p-3 flex items-center justify-between">
                      <div>
                        <p className="text-xs font-bold text-gray-900">{item.name}</p>
                        <p className="text-[10px] text-gray-400">{item.price.toLocaleString('fr-FR')} FCFA / unité</p>
                      </div>
                      <div className="flex items-center gap-2">
                        <Input
                          type="number"
                          value={item.qty}
                          onChange={(e) => {
                            const val = Number(e.target.value) || 1
                            setSupplierOrderItems((prev) => prev.map((i) => (i.id === item.id ? { ...i, qty: val } : i)))
                          }}
                          className="w-14 bg-gray-100 rounded-xl text-center py-1 text-xs font-bold outline-none"
                        />
                        <Button
                          onClick={() => setSupplierOrderItems((prev) => prev.filter((i) => i.id !== item.id))}
                          className="p-1 text-gray-400 hover:text-red-600" aria-label="Supprimer"
                        >
                          <Trash2 size={14} />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Send CTA */}
              <Button
                onClick={() => {
                  if (supplierOrderType === 'whatsapp_informal') {
                    const lines = supplierOrderItems.map((i) => `• ${i.qty} x ${i.name}`).join('\n')
                    const message = `Bonjour ${supplierWholesalerName},\n\nVoici ma commande de réapprovisionnement pour ${shopName} :\n${lines}\n\nMerci de me confirmer la disponibilité et la livraison !`
                    window.open(`https://wa.me/${supplierWholesalerPhone}?text=${encodeURIComponent(message)}`, '_blank')
                    showToast('Commande WhatsApp Direct générée et ouverte !')
                  } else {
                    showToast('Commande transmise via la plateforme Lynkstor (Statut : Nouvelle) !')
                  }
                  setSupplierOrderModalOpen(false)
                }}
                className={`w-full py-3.5 rounded-2xl text-white font-bold text-xs flex items-center justify-center gap-2 active:scale-95 transition-transform shadow-md ${supplierOrderType === 'whatsapp_informal' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-blue-600 hover:bg-blue-700'}`} aria-label="Envoyer"
              >
                <Send size={16} />
                <span>{supplierOrderType === 'whatsapp_informal' ? 'Transmettre via WhatsApp Direct 💬' : 'Envoyer la commande Lynkstor ⚡'}</span>
              </Button>
            </div>
          </div>
        )}

        {/* ── MODAL: JOURNAL D'ÉVÉNEMENTS (EVENT SOURCING LOCAL) ── */}
        {eventLogInspectorOpen && (
          <Dialog className="absolute inset-0 z-50 flex flex-col bg-white overflow-y-auto perspective-1000 animate-card-flip" label="Journal des événements" onDismiss={() => setEventLogInspectorOpen(false)}>
            <div className="flex items-center justify-between px-4 py-4 border-b border-gray-100 flex-shrink-0 bg-white sticky top-0 z-10">
              <Button onClick={() => setEventLogInspectorOpen(false)} className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200" aria-label="Retour">
                <ChevronLeft size={18} color="#1D2939" />
              </Button>
              <div className="text-center">
                <h2 className="text-base font-bold text-gray-900">Journal d'Événements Métier</h2>
                <p className="text-[11px] text-emerald-600 font-medium">Event Sourcing Local & Synchronisation</p>
              </div>
              <Button onClick={() => setEventLogInspectorOpen(false)} className="p-2 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-500" aria-label="Fermer">
                <X size={18} />
              </Button>
            </div>

            <div className="p-4 space-y-4 flex-1">
              <div className="p-3.5 bg-emerald-50 border border-emerald-100 rounded-2xl text-xs text-emerald-900 space-y-1">
                <p className="font-bold flex items-center gap-1.5">
                  <CheckCircle size={16} className="text-emerald-600" />
                  <span>Architecture Event-Sourcing Immuable (§5.1)</span>
                </p>
                <p className="text-[11px] text-emerald-800 leading-relaxed">
                  Chaque vente, mouvement de stock ou action est tracé sous forme d'événement immuable avec UUID unique.
                </p>
              </div>

              <div className="space-y-2">
                {eventLogList.map((evt) => (
                  <div key={evt.id} className="bg-white border border-gray-200 rounded-2xl p-3.5 space-y-1.5 shadow-2xs">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-bold">
                          {evt.type}
                        </span>
                        <span className="text-[10px] font-bold text-gray-400">{evt.id}</span>
                      </div>
                      <span className="text-[10px] text-gray-400">{evt.date}</span>
                    </div>
                    <p className="text-xs font-semibold text-gray-900">{evt.payload}</p>
                    <div className="flex justify-between items-center pt-1 border-t border-gray-100 text-[10px]">
                      <span className="text-gray-400">Statut sync :</span>
                      <span className="font-bold text-emerald-600 flex items-center gap-1">
                        <Check size={12} /> {evt.syncStatus}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </Dialog>
        )}

        {/* ── MODAL: GESTION DES DÉPENSES (OPEX) ── */}
        <ExpenseManagementModal
          open={expenseManagementModalOpen}
          onClose={() => setExpenseManagementModalOpen(false)}
          expenses={expenses}
          setExpenses={setExpenses}
          showToast={showToast}
          shopName={shopName}
        />

        {/* Screen content — each destination remains mounted to preserve work in progress. */}
        <main id="main-content" className="lk-page-area flex-1 overflow-hidden relative">
          <div className="lk-page-stack w-full h-full">
            <section hidden={tab !== 'accueil'} aria-label="Accueil"><AccueilScreen shopName={shopName} shopCity={shopCity} syncTransport={syncTransport} onOpenReporting={() => setReportingModalOpen(true)} onOpenCashClosure={() => setCashClosureModalOpen(true)} onOpenCreditLedger={() => setCreditLedgerModalOpen(true)} onOpenClientPwa={() => setClientPwaModalOpen(true)} onOpenLoyaltyPromotions={() => setLoyaltyPromotionsModalOpen(true)} onOpenExpenses={() => setExpenseManagementModalOpen(true)} expenses={expenses} creditAccounts={creditAccounts} products={products} /></section>
            <section hidden={tab !== 'vente'} aria-label="Vente"><VenteScreen carts={carts} setCarts={setCarts} activeCartId={activeCartId} setActiveCartId={setActiveCartId} cartOpen={cartOpen} setCartOpen={setCartOpen} products={internalSaleProducts} setProducts={setProducts} creditAccounts={creditAccounts} setCreditAccounts={setCreditAccounts} activeSector={sector} onSetCatalogueDraftPrice={setCatalogueDraftPrice} onActivateCatalogueProduct={activateCatalogueProduct} onDeductCatalogueStock={deductCatalogueStockForSale} catalogueDisplay={catalogueDisplay} showCatalogueImages={showInternalCatalogueImages} showToast={showToast} /></section>
            <section hidden={tab !== 'stock'} aria-label="Stock"><StockScreen products={products} setProducts={setProducts} stockMode={stockMode} setStockMode={setStockMode} activeSector={sector} showToast={showToast} stagedStockChanges={stagedStockChanges} setStagedStockChanges={setStagedStockChanges} setPendingMovementReasonSource={setPendingMovementReasonSource} setMovementReasonModalOpen={setMovementReasonModalOpen} initialDetailStock={initialDetailStock} setInitialDetailStock={setInitialDetailStock} selectedProductForDetail={selectedProductForDetail} setSelectedProductForDetail={setSelectedProductForDetail} onCatalogueProductsSelected={addSelectedCatalogueProducts} onActivateCatalogueProduct={activateCatalogueProduct} catalogueDisplay={catalogueDisplay} showCatalogueImages={showInternalCatalogueImages} /></section>
            <section hidden={tab !== 'assistant'} aria-label="Assistant"><AssistantScreen creditAccounts={creditAccounts} setCreditAccounts={setCreditAccounts} shopName={shopName} /></section>
          </div>
        </main>

        <LynkstorBottomNavigation activeIndex={tab} items={workspaceNavItems} onTap={changeTab} />
      </div>
    </div>
  )
}

export default function App() {
  const [onboardingData, setOnboardingData] = useState<OnboardingData | null>(() => {
    const session = loadShopSession()
    return session ? { ...session, phoneNumber: '', catalogueSelections: [], catalogueReviewAcknowledged: false } : null
  })
  const [appStage, setAppStage] = useState<'onboarding' | 'app'>(() => loadShopSession() ? 'app' : 'onboarding')
  const [shopName, setShopName] = useState(() => loadShopSession()?.shopName ?? 'Épicerie du Marché Central')
  const [shopCity, setShopCity] = useState(() => loadShopSession()?.shopCity ?? 'Douala')
  const [sector, setSector] = useState(() => loadShopSession()?.sector ?? 'Épicerie')

  const handleOnboardingComplete = (data: OnboardingData) => {
    setOnboardingData(data)
    saveShopSession({ tenantId: data.tenantId, shopName: data.shopName, shopCity: data.shopCity, sector: data.sector, categories: data.categories })
    if (data.shopName) setShopName(data.shopName)
    if (data.shopCity) setShopCity(data.shopCity)
    if (data.sector) setSector(data.sector)
    setAppStage('app')
  }

  if (appStage === 'onboarding' || !onboardingData) {
    return <OnboardingFlow onComplete={handleOnboardingComplete} />
  }

  return (
    <MainAppShell
      tenantId={onboardingData.tenantId}
      shopName={shopName}
      shopCity={shopCity}
      sector={sector}
      catalogueSelections={onboardingData.catalogueSelections}
      catalogueReviewAcknowledged={onboardingData.catalogueReviewAcknowledged}
      onResetOnboarding={() => { clearShopSession(); setOnboardingData(null); setAppStage('onboarding') }}
    />
  )
}
