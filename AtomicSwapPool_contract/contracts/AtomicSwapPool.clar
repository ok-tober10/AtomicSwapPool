
;; title: AtomicSwapPool
;; version: 1.0.0
;; summary: Cross-chain AMM liquidity pool using atomic swaps between BTC and STX
;; description: This contract implements an automated market maker (AMM) that enables
;;              atomic swaps between Bitcoin and STX tokens with liquidity provision
;;              and fee collection mechanisms.

;; traits
;;

;; token definitions
(define-fungible-token pool-token)

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-insufficient-liquidity (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-swap-expired (err u105))
(define-constant err-swap-not-found (err u106))
(define-constant err-swap-already-completed (err u107))
(define-constant err-invalid-hash (err u108))
(define-constant err-slippage-exceeded (err u109))

;; Fee in basis points (e.g., 30 = 0.3%)
(define-constant fee-rate u30)
(define-constant fee-denominator u10000)

;; data vars
(define-data-var stx-reserve uint u0)
(define-data-var btc-reserve uint u0)
(define-data-var total-liquidity uint u0)
(define-data-var swap-counter uint u0)

;; data maps
(define-map liquidity-providers principal uint)
(define-map atomic-swaps
  uint
  {
    initiator: principal,
    btc-amount: uint,
    stx-amount: uint,
    btc-address: (string-ascii 64),
    hash-lock: (buff 32),
    timeout: uint,
    completed: bool,
    cancelled: bool
  }
)

;; Stores the secret for completed swaps
(define-map swap-secrets uint (buff 32))

;; private functions

;; Simple integer square root using Newton's method
(define-private (isqrt (n uint))
  (if (<= n u1)
    n
    (let
      (
        (x0 (/ n u2))
        (x1 (/ (+ x0 (/ n x0)) u2))
        (x2 (/ (+ x1 (/ n x1)) u2))
        (x3 (/ (+ x2 (/ n x2)) u2))
        (x4 (/ (+ x3 (/ n x3)) u2))
        (x5 (/ (+ x4 (/ n x4)) u2))
      )
      x5
    )
  )
)

;; Return the minimum of two values
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

;; read only functions

;; Get the amount of BTC that would be received for a given STX amount
(define-read-only (get-btc-amount (stx-amount uint))
  (let (
    (stx-res (var-get stx-reserve))
    (btc-res (var-get btc-reserve))
    (fee-amount (/ (* stx-amount fee-rate) fee-denominator))
    (stx-amount-after-fee (- stx-amount fee-amount))
  )
    (if (or (is-eq stx-res u0) (is-eq btc-res u0))
      u0
      (/ (* stx-amount-after-fee btc-res) (+ stx-res stx-amount-after-fee))
    )
  )
)

;; Get the amount of STX that would be received for a given BTC amount
(define-read-only (get-stx-amount (btc-amount uint))
  (let (
    (stx-res (var-get stx-reserve))
    (btc-res (var-get btc-reserve))
    (stx-amount-before-fee (/ (* btc-amount stx-res) (+ btc-res btc-amount)))
    (fee-amount (/ (* stx-amount-before-fee fee-rate) fee-denominator))
  )
    (if (or (is-eq stx-res u0) (is-eq btc-res u0))
      u0
      (- stx-amount-before-fee fee-amount)
    )
  )
)

;; Get current pool reserves
(define-read-only (get-reserves)
  {
    stx-reserve: (var-get stx-reserve),
    btc-reserve: (var-get btc-reserve),
    total-liquidity: (var-get total-liquidity)
  }
)

;; Get user's liquidity provision
(define-read-only (get-user-liquidity (user principal))
  (default-to u0 (map-get? liquidity-providers user))
)

;; Get atomic swap details
(define-read-only (get-swap-details (swap-id uint))
  (map-get? atomic-swaps swap-id)
)

;; Get swap secret (only available for completed swaps)
(define-read-only (get-swap-secret (swap-id uint))
  (map-get? swap-secrets swap-id)
)

;; Check if a swap exists and is active
(define-read-only (is-swap-active (swap-id uint))
  (match (map-get? atomic-swaps swap-id)
    swap-data (and (not (get completed swap-data))
                   (not (get cancelled swap-data))
                   (< block-height (get timeout swap-data)))
    false
  )
)

;; public functions

;; Initialize the pool with initial liquidity
(define-public (initialize-pool (initial-stx uint) (initial-btc uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> initial-stx u0) err-invalid-amount)
    (asserts! (> initial-btc u0) err-invalid-amount)
    (asserts! (is-eq (var-get total-liquidity) u0) err-not-authorized)

    (try! (stx-transfer? initial-stx tx-sender (as-contract tx-sender)))

    (let ((initial-liquidity (isqrt (* initial-stx initial-btc))))
      (var-set stx-reserve initial-stx)
      (var-set btc-reserve initial-btc)
      (var-set total-liquidity initial-liquidity)
      (map-set liquidity-providers tx-sender initial-liquidity)
      (try! (ft-mint? pool-token initial-liquidity tx-sender))
      (ok initial-liquidity)
    )
  )
)

;; Add liquidity to the pool
(define-public (add-liquidity (stx-amount uint) (btc-amount uint) (min-liquidity uint))
  (let (
    (stx-res (var-get stx-reserve))
    (btc-res (var-get btc-reserve))
    (total-liq (var-get total-liquidity))
    (liquidity-minted (if (is-eq total-liq u0)
                        (isqrt (* stx-amount btc-amount))
                        (min (/ (* stx-amount total-liq) stx-res)
                             (/ (* btc-amount total-liq) btc-res))))
  )
    (asserts! (> stx-amount u0) err-invalid-amount)
    (asserts! (> btc-amount u0) err-invalid-amount)
    (asserts! (>= liquidity-minted min-liquidity) err-slippage-exceeded)

    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))

    (var-set stx-reserve (+ stx-res stx-amount))
    (var-set btc-reserve (+ btc-res btc-amount))
    (var-set total-liquidity (+ total-liq liquidity-minted))

    (map-set liquidity-providers tx-sender
             (+ (default-to u0 (map-get? liquidity-providers tx-sender)) liquidity-minted))

    (try! (ft-mint? pool-token liquidity-minted tx-sender))
    (ok liquidity-minted)
  )
)

;; Remove liquidity from the pool
(define-public (remove-liquidity (liquidity-amount uint) (min-stx uint) (min-btc uint))
  (let (
    (stx-res (var-get stx-reserve))
    (btc-res (var-get btc-reserve))
    (total-liq (var-get total-liquidity))
    (user-liquidity (default-to u0 (map-get? liquidity-providers tx-sender)))
    (stx-amount (/ (* liquidity-amount stx-res) total-liq))
    (btc-amount (/ (* liquidity-amount btc-res) total-liq))
  )
    (asserts! (> liquidity-amount u0) err-invalid-amount)
    (asserts! (>= user-liquidity liquidity-amount) err-insufficient-balance)
    (asserts! (>= stx-amount min-stx) err-slippage-exceeded)
    (asserts! (>= btc-amount min-btc) err-slippage-exceeded)

    (try! (ft-burn? pool-token liquidity-amount tx-sender))
    (try! (as-contract (stx-transfer? stx-amount tx-sender tx-sender)))

    (var-set stx-reserve (- stx-res stx-amount))
    (var-set btc-reserve (- btc-res btc-amount))
    (var-set total-liquidity (- total-liq liquidity-amount))

    (map-set liquidity-providers tx-sender (- user-liquidity liquidity-amount))

    (ok {stx-amount: stx-amount, btc-amount: btc-amount})
  )
)

;; Initiate an atomic swap (STX -> BTC)
(define-public (initiate-swap (stx-amount uint) (btc-amount uint) (btc-address (string-ascii 64))
                             (hash-lock (buff 32)) (timeout uint))
  (let (
    (swap-id (+ (var-get swap-counter) u1))
    (current-stx-res (var-get stx-reserve))
    (current-btc-res (var-get btc-reserve))
    (fee-amount (/ (* stx-amount fee-rate) fee-denominator))
    (stx-amount-after-fee (- stx-amount fee-amount))
    (expected-btc (get-btc-amount stx-amount-after-fee))
  )
    (asserts! (> stx-amount u0) err-invalid-amount)
    (asserts! (> btc-amount u0) err-invalid-amount)
    (asserts! (> timeout block-height) err-invalid-amount)
    (asserts! (>= expected-btc btc-amount) err-slippage-exceeded)
    (asserts! (<= btc-amount current-btc-res) err-insufficient-liquidity)

    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))

    (map-set atomic-swaps swap-id {
      initiator: tx-sender,
      btc-amount: btc-amount,
      stx-amount: stx-amount,
      btc-address: btc-address,
      hash-lock: hash-lock,
      timeout: timeout,
      completed: false,
      cancelled: false
    })

    (var-set swap-counter swap-id)
    (ok swap-id)
  )
)

;; Complete an atomic swap by revealing the secret
(define-public (complete-swap (swap-id uint) (secret (buff 32)))
  (let (
    (swap-data (unwrap! (map-get? atomic-swaps swap-id) err-swap-not-found))
    (hash-result (sha256 secret))
  )
    (asserts! (not (get completed swap-data)) err-swap-already-completed)
    (asserts! (not (get cancelled swap-data)) err-swap-already-completed)
    (asserts! (< block-height (get timeout swap-data)) err-swap-expired)
    (asserts! (is-eq hash-result (get hash-lock swap-data)) err-invalid-hash)

    (let (
      (stx-amount (get stx-amount swap-data))
      (btc-amount (get btc-amount swap-data))
      (fee-amount (/ (* stx-amount fee-rate) fee-denominator))
      (stx-amount-after-fee (- stx-amount fee-amount))
      (current-stx-res (var-get stx-reserve))
      (current-btc-res (var-get btc-reserve))
    )
      ;; Update reserves (add STX, remove BTC)
      (var-set stx-reserve (+ current-stx-res stx-amount-after-fee))
      (var-set btc-reserve (- current-btc-res btc-amount))

      ;; Mark swap as completed
      (map-set atomic-swaps swap-id (merge swap-data {completed: true}))
      (map-set swap-secrets swap-id secret)

      (ok true)
    )
  )
)

;; Cancel an expired atomic swap
(define-public (cancel-swap (swap-id uint))
  (let (
    (swap-data (unwrap! (map-get? atomic-swaps swap-id) err-swap-not-found))
  )
    (asserts! (not (get completed swap-data)) err-swap-already-completed)
    (asserts! (not (get cancelled swap-data)) err-swap-already-completed)
    (asserts! (or (>= block-height (get timeout swap-data))
                  (is-eq tx-sender (get initiator swap-data))) err-not-authorized)

    ;; Refund STX to initiator
    (try! (as-contract (stx-transfer? (get stx-amount swap-data)
                                     tx-sender (get initiator swap-data))))

    ;; Mark swap as cancelled
    (map-set atomic-swaps swap-id (merge swap-data {cancelled: true}))

    (ok true)
  )
)
