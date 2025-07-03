;; Title: StackScore Protocol - Reputation-Driven DeFi Lending Platform
;;
;; Summary: 
;; Next-generation lending infrastructure that leverages behavioral analytics
;; to unlock progressive capital efficiency on Bitcoin's Layer 2 ecosystem
;;
;; Description:
;; StackScore Protocol pioneers a sophisticated approach to decentralized lending
;; by introducing reputation-based capital allocation mechanisms built natively
;; for the Stacks blockchain. Our advanced scoring engine analyzes on-chain
;; behavior patterns to create dynamic lending terms that evolve with user
;; reliability. Through machine learning-inspired algorithms, borrowers earn
;; enhanced capital efficiency privileges including reduced collateral ratios,
;; premium interest rates, and exclusive lending tiers. The protocol creates
;; a self-sustaining ecosystem where financial responsibility translates directly
;; into measurable economic advantages, fundamentally reshaping how capital
;; flows within Bitcoin's extended ecosystem.
;;
;; Core Value Proposition: 
;; Where traditional protocols demand excessive over-collateralization,
;; StackScore enables proven users to access capital with significantly
;; reduced collateral requirements while maintaining robust risk management
;; through sophisticated behavioral economics and predictive modeling.

;; PROTOCOL CONSTANTS & ERROR DEFINITIONS

(define-constant CONTRACT-OWNER tx-sender)

;; Comprehensive error handling system
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-BALANCE (err u2))
(define-constant ERR-INVALID-AMOUNT (err u3))
(define-constant ERR-LOAN-NOT-FOUND (err u4))
(define-constant ERR-LOAN-DEFAULTED (err u5))
(define-constant ERR-INSUFFICIENT-SCORE (err u6))
(define-constant ERR-ACTIVE-LOAN (err u7))
(define-constant ERR-NOT-DUE (err u8))
(define-constant ERR-INVALID-DURATION (err u9))
(define-constant ERR-INVALID-LOAN-ID (err u10))

;; Reputation scoring framework
(define-constant MIN-SCORE u50)
(define-constant MAX-SCORE u100)
(define-constant MIN-LOAN-SCORE u70)

;; DATA STRUCTURES & STORAGE MAPS

;; Advanced user reputation profiles with behavioral tracking
(define-map UserScores
  { user: principal }
  {
    score: uint,
    total-borrowed: uint,
    total-repaid: uint,
    loans-taken: uint,
    loans-repaid: uint,
    last-update: uint,
  }
)

;; Detailed loan registry with comprehensive metadata
(define-map Loans
  { loan-id: uint }
  {
    borrower: principal,
    amount: uint,
    collateral: uint,
    due-height: uint,
    interest-rate: uint,
    is-active: bool,
    is-defaulted: bool,
    repaid-amount: uint,
  }
)

;; Active loan portfolio management per user
(define-map UserLoans
  { user: principal }
  { active-loans: (list 20 uint) }
)

;; GLOBAL STATE VARIABLES

(define-data-var next-loan-id uint u0)
(define-data-var total-stx-locked uint u0)

;; CORE PUBLIC FUNCTIONS

;; Bootstrap user reputation profile
;; Establishes baseline scoring metrics for protocol participation
(define-public (initialize-score)
  (let ((sender tx-sender))
    (asserts! (is-none (map-get? UserScores { user: sender })) ERR-UNAUTHORIZED)
    (ok (map-set UserScores { user: sender } {
      score: MIN-SCORE,
      total-borrowed: u0,
      total-repaid: u0,
      loans-taken: u0,
      loans-repaid: u0,
      last-update: stacks-block-height,
    }))
  )
)

;; Execute smart loan origination with dynamic pricing
;; Implements reputation-based collateral optimization and risk assessment
(define-public (request-loan
    (amount uint)
    (collateral uint)
    (duration uint)
  )
  (let (
      (sender tx-sender)
      (loan-id (+ (var-get next-loan-id) u1))
      (user-score (unwrap! (map-get? UserScores { user: sender }) ERR-UNAUTHORIZED))
      (active-loans (default-to { active-loans: (list) } (map-get? UserLoans { user: sender })))
    )
    ;; Multi-layer eligibility verification
    (asserts! (>= (get score user-score) MIN-LOAN-SCORE) ERR-INSUFFICIENT-SCORE)
    (asserts! (<= (len (get active-loans active-loans)) u5) ERR-ACTIVE-LOAN)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (and (> duration u0) (<= duration u52560)) ERR-INVALID-DURATION)
    ;; Maximum 1 year duration
    ;; Intelligent collateral calculation based on reputation score
    (let ((required-collateral (calculate-required-collateral amount (get score user-score))))
      (asserts! (>= collateral required-collateral) ERR-INSUFFICIENT-BALANCE)
      ;; Execute collateral lock mechanism
      (try! (stx-transfer? collateral sender (as-contract tx-sender)))
      ;; Initialize comprehensive loan structure
      (map-set Loans { loan-id: loan-id } {
        borrower: sender,
        amount: amount,
        collateral: collateral,
        due-height: (+ stacks-block-height duration),
        interest-rate: (calculate-interest-rate (get score user-score)),
        is-active: true,
        is-defaulted: false,
        repaid-amount: u0,
      })
      ;; Maintain user loan portfolio registry
      (try! (update-user-loans sender loan-id))
      ;; Process capital disbursement
      (as-contract (try! (stx-transfer? amount tx-sender sender)))
      ;; Update global protocol state
      (var-set next-loan-id loan-id)
      (var-set total-stx-locked (+ (var-get total-stx-locked) collateral))
      (ok loan-id)
    )
  )
)

;; Process intelligent loan repayment with reputation updates
;; Handles partial payments and executes automatic collateral release
(define-public (repay-loan
    (loan-id uint)
    (amount uint)
  )
  (let (
      (sender tx-sender)
      (loan (unwrap! (map-get? Loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    )
    ;; Strict authorization and validation checks
    (asserts! (is-eq sender (get borrower loan)) ERR-UNAUTHORIZED)
    (asserts! (get is-active loan) ERR-LOAN-NOT-FOUND)
    (asserts! (not (get is-defaulted loan)) ERR-LOAN-DEFAULTED)
    (asserts! (<= loan-id (var-get next-loan-id)) ERR-INVALID-LOAN-ID)
    ;; Calculate total outstanding obligation
    (let ((total-due (calculate-total-due loan)))
      (asserts! (>= amount u0) ERR-INVALID-AMOUNT)
      ;; Execute repayment transaction
      (try! (stx-transfer? amount sender (as-contract tx-sender)))
      ;; Update loan repayment tracking
      (let ((new-repaid-amount (+ (get repaid-amount loan) amount)))
        (map-set Loans { loan-id: loan-id }
          (merge loan {
            repaid-amount: new-repaid-amount,
            is-active: (< new-repaid-amount total-due),
          })
        )
        ;; Execute loan completion procedures
        (if (>= new-repaid-amount total-due)
          (begin
            (try! (update-credit-score sender true loan))
            (as-contract (try! (stx-transfer? (get collateral loan) tx-sender sender)))
            (var-set total-stx-locked
              (- (var-get total-stx-locked) (get collateral loan))
            )
          )
          true
        )
        (ok true)
      )
    )
  )
)

;; ADVANCED CALCULATION ALGORITHMS

;; Reputation-based collateral optimization engine
;; Implements progressive capital efficiency unlocking mechanism
(define-private (calculate-required-collateral
    (amount uint)
    (score uint)
  )
  (let ((collateral-ratio (- u100 (/ (* score u50) u100))))
    (/ (* amount collateral-ratio) u100)
  )
)

;; Dynamic interest rate calculation based on reputation metrics
;; Rewards high-reputation users with preferential pricing
(define-private (calculate-interest-rate (score uint))
  (let ((base-rate u10))
    (- base-rate (/ (* score u5) u100))
  )
)

;; Comprehensive debt obligation calculator with interest accrual
(define-private (calculate-total-due (loan {
  borrower: principal,
  amount: uint,
  collateral: uint,
  due-height: uint,
  interest-rate: uint,
  is-active: bool,
  is-defaulted: bool,
  repaid-amount: uint,
}))
  (let ((interest (* (get amount loan) (get interest-rate loan))))
    (+ (get amount loan) (/ interest u100))
  )
)

;; Sophisticated reputation scoring algorithm with behavioral analysis
;; Implements positive reinforcement for responsible financial behavior
(define-private (update-credit-score
    (user principal)
    (success bool)
    (loan {
      borrower: principal,
      amount: uint,
      collateral: uint,
      due-height: uint,
      interest-rate: uint,
      is-active: bool,
      is-defaulted: bool,
      repaid-amount: uint,
    })
  )
  (let (
      (current-score (unwrap! (map-get? UserScores { user: user }) ERR-UNAUTHORIZED))
      (new-score (if success
        (if (<= (+ (get score current-score) u2) MAX-SCORE)
          (+ (get score current-score) u2)
          MAX-SCORE
        )
        (if (>= (- (get score current-score) u10) MIN-SCORE)
          (- (get score current-score) u10)
          MIN-SCORE
        )
      ))
    )
    ;; Execute comprehensive profile update
    (if success
      (map-set UserScores { user: user }
        (merge current-score {
          score: new-score,
          total-repaid: (+ (get total-repaid current-score) (get amount loan)),
          loans-repaid: (+ (get loans-repaid current-score) u1),
          last-update: stacks-block-height,
        })
      )
      (map-set UserScores { user: user }
        (merge current-score {
          score: new-score,
          last-update: stacks-block-height,
        })
      )
    )
    (ok true)
  )
)

;; Advanced portfolio management system
;; Maintains real-time tracking of user's active lending positions
(define-private (update-user-loans
    (user principal)
    (loan-id uint)
  )
  (let ((user-loans (default-to { active-loans: (list) } (map-get? UserLoans { user: user }))))
    (map-set UserLoans { user: user } { active-loans: (unwrap! (as-max-len? (append (get active-loans user-loans) loan-id) u20)
      ERR-ACTIVE-LOAN
    ) }
    )
    (ok true)
  )
)

;; PUBLIC READ-ONLY INTERFACE

;; Retrieve detailed user reputation profile
(define-read-only (get-user-score (user principal))
  (map-get? UserScores { user: user })
)

;; Access comprehensive loan information
(define-read-only (get-loan (loan-id uint))
  (map-get? Loans { loan-id: loan-id })
)

;; Query user's active loan portfolio
(define-read-only (get-user-active-loans (user principal))
  (map-get? UserLoans { user: user })
)

;; PROTOCOL ADMINISTRATION FUNCTIONS

;; Automated default management system
;; Implements risk mitigation through systematic default processing
(define-public (mark-loan-defaulted (loan-id uint))
  (let ((loan (unwrap! (map-get? Loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (>= stacks-block-height (get due-height loan)) ERR-NOT-DUE)
    (asserts! (get is-active loan) ERR-LOAN-NOT-FOUND)
    (asserts! (<= loan-id (var-get next-loan-id)) ERR-INVALID-LOAN-ID)
    ;; Execute default processing workflow
    (map-set Loans { loan-id: loan-id }
      (merge loan {
        is-defaulted: true,
        is-active: false,
      })
    )
    ;; Apply reputation penalty for default behavior
    (try! (update-credit-score (get borrower loan) false loan))
    (ok true)
  )
)
