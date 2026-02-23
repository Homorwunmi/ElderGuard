;; ElderGuard - Social Recovery Wallet for Senior Citizens
;; Built on the Stacks Blockchain in Clarity
;; Adult children (guardians) can help recover access if the owner loses their key

;; ============================================================
;; Constants
;; ============================================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-NOT-GUARDIAN (err u101))
(define-constant ERR-ALREADY-GUARDIAN (err u102))
(define-constant ERR-GUARDIAN-LIMIT (err u103))
(define-constant ERR-NO-RECOVERY-ACTIVE (err u104))
(define-constant ERR-RECOVERY-ACTIVE (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-INSUFFICIENT-VOTES (err u107))
(define-constant ERR-RECOVERY-EXPIRED (err u108))
(define-constant ERR-INVALID-AMOUNT (err u109))
(define-constant ERR-GUARDIAN-NOT-FOUND (err u110))
(define-constant ERR-TIMELOCK-ACTIVE (err u111))

(define-constant MAX-GUARDIANS u5)
(define-constant RECOVERY-THRESHOLD u2)       ;; Min guardian votes to recover
(define-constant RECOVERY-WINDOW u1440)       ;; ~10 days in blocks (144 blocks/day)
(define-constant SPEND-TIMELOCK u144)         ;; ~1 day delay for large transfers

;; ============================================================
;; Data Variables
;; ============================================================

(define-data-var wallet-owner principal tx-sender)
(define-data-var guardian-count uint u0)
(define-data-var recovery-active bool false)
(define-data-var recovery-target (optional principal) none)
(define-data-var recovery-vote-count uint u0)
(define-data-var recovery-initiated-at uint u0)
(define-data-var pending-transfer-amount uint u0)
(define-data-var pending-transfer-to (optional principal) none)
(define-data-var pending-transfer-at uint u0)

;; ============================================================
;; Data Maps
;; ============================================================

;; Registered adult children / guardians
(define-map guardians principal bool)

;; Tracks which guardian has voted during active recovery
(define-map recovery-votes principal bool)

;; Guardian index for enumeration (id -> principal)
(define-map guardian-index uint principal)

;; ============================================================
;; Read-Only Functions
;; ============================================================

(define-read-only (get-owner)
  (var-get wallet-owner))

(define-read-only (get-guardian-count)
  (var-get guardian-count))

(define-read-only (is-guardian (addr principal))
  (default-to false (map-get? guardians addr)))

(define-read-only (get-recovery-status)
  {
    active: (var-get recovery-active),
    target: (var-get recovery-target),
    votes: (var-get recovery-vote-count),
    initiated-at: (var-get recovery-initiated-at),
    threshold: RECOVERY-THRESHOLD
  })

(define-read-only (get-pending-transfer)
  {
    amount: (var-get pending-transfer-amount),
    to: (var-get pending-transfer-to),
    queued-at: (var-get pending-transfer-at)
  })

(define-read-only (has-voted (guardian principal))
  (default-to false (map-get? recovery-votes guardian)))

(define-read-only (get-balance)
  (stx-get-balance (as-contract tx-sender)))

;; ============================================================
;; Private Helpers
;; ============================================================

(define-private (is-owner)
  (is-eq tx-sender (var-get wallet-owner)))

(define-private (clear-recovery)
  (begin
    (var-set recovery-active false)
    (var-set recovery-target none)
    (var-set recovery-vote-count u0)
    (var-set recovery-initiated-at u0)))

;; ============================================================
;; Guardian Management (Owner Only)
;; ============================================================

;; Add an adult child as a recovery guardian
(define-public (add-guardian (guardian principal))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (not (var-get recovery-active)) ERR-RECOVERY-ACTIVE)
    (asserts! (< (var-get guardian-count) MAX-GUARDIANS) ERR-GUARDIAN-LIMIT)
    (asserts! (not (is-guardian guardian)) ERR-ALREADY-GUARDIAN)
    (map-set guardians guardian true)
    (map-set guardian-index (var-get guardian-count) guardian)
    (var-set guardian-count (+ (var-get guardian-count) u1))
    (ok true)))

;; Remove a guardian
(define-public (remove-guardian (guardian principal))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (not (var-get recovery-active)) ERR-RECOVERY-ACTIVE)
    (asserts! (is-guardian guardian) ERR-GUARDIAN-NOT-FOUND)
    (map-delete guardians guardian)
    (var-set guardian-count (- (var-get guardian-count) u1))
    (ok true)))

;; ============================================================
;; Deposit
;; ============================================================

(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (stx-transfer? amount tx-sender (as-contract tx-sender))))

;; ============================================================
;; Spending (Owner Only)
;; ============================================================

;; Instant small transfer
(define-public (transfer (amount uint) (recipient principal))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (as-contract (stx-transfer? amount tx-sender recipient))))

;; Queue a large transfer with a 1-day safety timelock
(define-public (queue-large-transfer (amount uint) (recipient principal))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (var-set pending-transfer-amount amount)
    (var-set pending-transfer-to (some recipient))
    (var-set pending-transfer-at burn-block-height)
    (ok true)))

;; Execute the queued transfer after timelock expires
(define-public (execute-pending-transfer)
  (let (
    (queued-at (var-get pending-transfer-at))
    (amount    (var-get pending-transfer-amount))
    (recipient (var-get pending-transfer-to))
  )
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-some recipient) ERR-INVALID-AMOUNT)
    (asserts! (>= (- burn-block-height queued-at) SPEND-TIMELOCK) ERR-TIMELOCK-ACTIVE)
    (var-set pending-transfer-amount u0)
    (var-set pending-transfer-to none)
    (var-set pending-transfer-at u0)
    (as-contract (stx-transfer? amount tx-sender (unwrap-panic recipient)))))

;; Cancel a queued transfer
(define-public (cancel-pending-transfer)
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (var-set pending-transfer-amount u0)
    (var-set pending-transfer-to none)
    (var-set pending-transfer-at u0)
    (ok true)))

;; ============================================================
;; Social Recovery Flow
;; ============================================================

;; Step 1: A guardian proposes a new owner (counts as first vote)
(define-public (initiate-recovery (new-owner principal))
  (begin
    (asserts! (is-guardian tx-sender) ERR-NOT-GUARDIAN)
    (asserts! (not (var-get recovery-active)) ERR-RECOVERY-ACTIVE)
    (var-set recovery-active true)
    (var-set recovery-target (some new-owner))
    (var-set recovery-initiated-at burn-block-height)
    (var-set recovery-vote-count u1)
    (map-set recovery-votes tx-sender true)
    (ok true)))

;; Step 2: Other guardians cast their approval votes
(define-public (approve-recovery)
  (begin
    (asserts! (is-guardian tx-sender) ERR-NOT-GUARDIAN)
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (asserts! (not (has-voted tx-sender)) ERR-ALREADY-VOTED)
    (asserts!
      (<= (- burn-block-height (var-get recovery-initiated-at)) RECOVERY-WINDOW)
      ERR-RECOVERY-EXPIRED)
    (map-set recovery-votes tx-sender true)
    (var-set recovery-vote-count (+ (var-get recovery-vote-count) u1))
    (ok true)))

;; Step 3: Any guardian executes recovery once threshold is met
(define-public (execute-recovery)
  (let ((new-owner (unwrap! (var-get recovery-target) ERR-NO-RECOVERY-ACTIVE)))
    (asserts! (is-guardian tx-sender) ERR-NOT-GUARDIAN)
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (asserts!
      (>= (var-get recovery-vote-count) RECOVERY-THRESHOLD)
      ERR-INSUFFICIENT-VOTES)
    (asserts!
      (<= (- burn-block-height (var-get recovery-initiated-at)) RECOVERY-WINDOW)
      ERR-RECOVERY-EXPIRED)
    (var-set wallet-owner new-owner)
    (clear-recovery)
    (ok true)))

;; Owner can veto an active recovery attempt
(define-public (cancel-recovery)
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (clear-recovery)
    (ok true)))

;; Anyone can clean up an expired recovery
(define-public (expire-recovery)
  (begin
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (asserts!
      (> (- burn-block-height (var-get recovery-initiated-at)) RECOVERY-WINDOW)
      ERR-RECOVERY-ACTIVE)
    (clear-recovery)
    (ok true)))
