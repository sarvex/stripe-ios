//
//  SavedPaymentMethodsViewController.swift
//  StripePaymentSheet
//

import Foundation
@_spi(STP) import StripeCore
@_spi(STP) import StripePayments
@_spi(STP) import StripePaymentsUI
@_spi(STP) import StripeUICore
import UIKit

protocol SavedPaymentMethodsViewControllerDelegate: AnyObject {
    func savedPaymentMethodsViewControllerShouldConfirm(_ savedPaymentMethodsViewController: SavedPaymentMethodsViewController,
    with paymentOption: PaymentOption,
completion: @escaping(SavedPaymentMethodsSheetResult) -> Void)
    func savedPaymentMethodsViewControllerDidCancel(_ savedPaymentMethodsViewController: SavedPaymentMethodsViewController)
    func savedPaymentMethodsViewControllerDidFinish(_ savedPaymentMethodsViewController: SavedPaymentMethodsViewController)
}

@objc(STP_Internal_SavedPaymentMethodsViewController)
class SavedPaymentMethodsViewController: UIViewController {

    // MARK: - Read-only Properties
    let savedPaymentMethods: [STPPaymentMethod]
    let isApplePayEnabled: Bool
    let configuration: SavedPaymentMethodsSheet.Configuration

    // MARK: - Writable Properties
    weak var delegate: SavedPaymentMethodsViewControllerDelegate?
    weak var savedPaymentMethodsSheetDelegate: SavedPaymentMethodsSheetDelegate?
    private(set) var isDismissable: Bool = true
    enum Mode {
        case selectingSaved
        case addingNewWithSetupIntent
        case addingNewPaymentMethodAttachToCustomer
    }

    private var mode: Mode
    private(set) var error: Error?
    private(set) var intent: Intent?
    private var addPaymentMethodViewController: SavedPaymentMethodsAddPaymentMethodViewController?

    var selectedPaymentOption: PaymentOption? {
        switch mode {
        case .addingNewWithSetupIntent, .addingNewPaymentMethodAttachToCustomer:
            if let paymentOption = addPaymentMethodViewController?.paymentOption {
                return paymentOption
            }
            return nil
        case .selectingSaved:
            return savedPaymentOptionsViewController.selectedPaymentOption
        }
    }
    
    // MARK: - Views
    internal lazy var navigationBar: SheetNavigationBar = {
        let navBar = SheetNavigationBar(isTestMode: configuration.apiClient.isTestmode,
                                        appearance: configuration.appearance)
        navBar.delegate = self
        return navBar
    }()

    private lazy var savedPaymentOptionsViewController: SavedPaymentMethodsCollectionViewController = {
        let showApplePay = isApplePayEnabled
        return SavedPaymentMethodsCollectionViewController(
            savedPaymentMethods: savedPaymentMethods,
            savedPaymentMethodsConfiguration: self.configuration,
            configuration: .init(
                showApplePay: showApplePay,
                autoSelectDefaultBehavior: savedPaymentMethods.isEmpty ? .none : .onlyIfMatched
            ),
            appearance: configuration.appearance,
            savedPaymentMethodsSheetDelegate: savedPaymentMethodsSheetDelegate,
            delegate: self
        )
    }()
    private lazy var paymentContainerView: DynamicHeightContainerView = {
        return DynamicHeightContainerView()
    }()
    private lazy var actionButton: ConfirmButton = {
        let callToAction: ConfirmButton.CallToActionType = {
            switch (mode) {
            case .selectingSaved:
//                if let confirm = configuration.primaryButtonLabel {
                    return .custom(title: STPLocalizedString(
                        "Confirm",
                        "A button used to confirm selecting a saved payment method"
                    ))
  //              }
            case .addingNewWithSetupIntent, .addingNewPaymentMethodAttachToCustomer:
                return .setup
            }
        }()

//            switch intent {
//            case .paymentIntent(let paymentIntent):
//                return .pay(amount: paymentIntent.amount, currency: paymentIntent.currency)
//            case .setupIntent:
//                return .setup
//            }
//        }()

        let button = ConfirmButton(
            callToAction: callToAction,
            applePayButtonType: .plain,
            appearance: configuration.appearance,
            didTap: { [weak self] in
                self?.didTapActionButton()
            }
        )
        return button
    }()
    private lazy var headerLabel: UILabel = {
        return PaymentSheetUI.makeHeaderLabel(appearance: configuration.appearance)
    }()

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(
        savedPaymentMethods: [STPPaymentMethod],
        configuration: SavedPaymentMethodsSheet.Configuration,
        isApplePayEnabled: Bool,
        savedPaymentMethodsSheetDelegate: SavedPaymentMethodsSheetDelegate?,
        delegate: SavedPaymentMethodsViewControllerDelegate
    ) {
        self.savedPaymentMethods = savedPaymentMethods
        self.configuration = configuration
        self.isApplePayEnabled = isApplePayEnabled
        self.savedPaymentMethodsSheetDelegate = savedPaymentMethodsSheetDelegate
        self.delegate = delegate
        self.mode = .selectingSaved
        self.addPaymentMethodViewController = nil
                super.init(nibName: nil, bundle: nil)

        self.view.backgroundColor = configuration.appearance.colors.background
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        let stackView = UIStackView(arrangedSubviews: [
            headerLabel,
           //walletHeader,
            paymentContainerView,
            actionButton,
            //errorLabel,
            //, bottomNoticeTextField
        ])
        stackView.directionalLayoutMargins = PaymentSheetUI.defaultMargins
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.spacing = PaymentSheetUI.defaultPadding
        stackView.axis = .vertical
        stackView.bringSubviewToFront(headerLabel)
        stackView.setCustomSpacing(32, after: paymentContainerView)
        stackView.setCustomSpacing(0, after: actionButton)

        paymentContainerView.directionalLayoutMargins = .insets(
            leading: -PaymentSheetUI.defaultSheetMargins.leading,
            trailing: -PaymentSheetUI.defaultSheetMargins.trailing
        )
        [stackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor, constant: -PaymentSheetUI.defaultSheetMargins.bottom),
        ])

        updateUI(animated: false)
    }

    // MARK: Private Methods
    private func updateUI(animated: Bool = true) {

        // Update our views (starting from the top of the screen):
        configureNavBar()

        switch(mode) {
        case .selectingSaved:
            actionButton.isHidden = true
            if let text = configuration.selectingSavedCustomHeaderText, !text.isEmpty {
                headerLabel.text = text
            } else {
                headerLabel.text = STPLocalizedString(
                    "Select your payment method",
                    "Title shown above a carousel containing the customer's payment methods")
            }
        case .addingNewWithSetupIntent, .addingNewPaymentMethodAttachToCustomer:
            actionButton.isHidden = false
            headerLabel.text = STPLocalizedString(
                "Add your payment information",
                "Title shown above a form where the customer can enter payment information like credit card details, email, billing address, etc."
            )
        }

        guard let contentViewController = contentViewControllerFor(mode: mode) else {
            // TODO: if we return nil here, it means we didn't create a
            // view controller, and if this happens, it is most likely because didn't
            // properly create setupIntent -- how do we want to handlet his situation?
            return
        }

        switchContentIfNecessary(to: contentViewController, containerView: paymentContainerView)
    }
    private func contentViewControllerFor(mode: Mode) -> UIViewController? {
        if mode == .addingNewWithSetupIntent || mode == .addingNewPaymentMethodAttachToCustomer {
            return addPaymentMethodViewController
        }
        return savedPaymentOptionsViewController
    }

    private func configureNavBar() {
        navigationBar.setStyle(
            {
                switch mode {
                case .selectingSaved:
                    if self.savedPaymentOptionsViewController.hasRemovablePaymentMethods {
                        self.configureEditSavedPaymentMethodsButton()
                        return .close(showAdditionalButton: true)
                    } else {
                        self.navigationBar.additionalButton.removeTarget(
                            self, action: #selector(didSelectEditSavedPaymentMethodsButton),
                            for: .touchUpInside)
                        return .close(showAdditionalButton: false)
                    }
                case .addingNewWithSetupIntent, .addingNewPaymentMethodAttachToCustomer:
                    self.navigationBar.additionalButton.removeTarget(
                        self, action: #selector(didSelectEditSavedPaymentMethodsButton),
                        for: .touchUpInside)
                    return savedPaymentMethods.isEmpty ? .close(showAdditionalButton: false) : .back
                }
            }())

    }

    func fetchSetupIntent(clientSecret: String, completion: @escaping ((Result<STPSetupIntent, Error>) -> Void) ) {
        configuration.apiClient.retrieveSetupIntentWithPreferences(withClientSecret: clientSecret) { result in
            switch result {
            case .success(let setupIntent):
                completion(.success(setupIntent))
            case .failure(let error):
                completion(.failure(error))
            }

        }
    }
    private func didTapActionButton() {
        guard mode == .addingNewWithSetupIntent || mode == .addingNewPaymentMethodAttachToCustomer,
        let newPaymentOption = addPaymentMethodViewController?.paymentOption else {
            //Button will only appear while adding a new payment method
            return
        }
        if mode == .addingNewWithSetupIntent {
            addPaymentOption(paymentOption: newPaymentOption)
        } else if mode == .addingNewPaymentMethodAttachToCustomer {
            addPaymentOptionToCustomer(paymentOption: newPaymentOption)
        }

    }
    private func addPaymentOption(paymentOption: PaymentOption) {
        guard case .new(_) = paymentOption else {
            return
        }
        self.delegate?.savedPaymentMethodsViewControllerShouldConfirm(self, with: paymentOption, completion: { result in
            switch(result) {
            case .canceled:
                self.updateUI()
            case .failed(let error):
                //TODO
                print(error)
            case .completed(let intent):
                self.actionButton.update(state: .succeeded, animated: true) {
                    guard let intent = intent as? STPSetupIntent,
                          let paymentMethod = intent.paymentMethod else {
                        //TODO: error!?! or maybe just make our type system more strict
                        self.updateUI()
                        return
                    }
                    let paymentOptionSelection = SavedPaymentMethodsSheet.PaymentOptionSelection.newPaymentMethod(paymentMethod)
                    self.setSelectablePaymentMethodAndClose(paymentOptionSelection: paymentOptionSelection)
                }

            }
        })
    }
   
    private func addPaymentOptionToCustomer(paymentOption: PaymentOption) {
        if case .new(let confirmParams) = paymentOption  {
            configuration.apiClient.createPaymentMethod(with: confirmParams.paymentMethodParams) { paymentMethod, error in
                if let error = error {
                    self.savedPaymentMethodsSheetDelegate?.didFail(with: .createPaymentMethod(error))
                    return
                }
                guard let paymentMethod = paymentMethod else {
                    // TODO: test UI to make sure we fail gracefully
                    self.savedPaymentMethodsSheetDelegate?.didFail(with: .unknown(debugDescription: "No payment method available"))
                    return
                }
                self.configuration.customerContext.attachPaymentMethod(toCustomer: paymentMethod) { error in
                    guard error == nil else {
                        //TODO: Handle errors properly
                        self.savedPaymentMethodsSheetDelegate?.didFail(with: .attachPaymentMethod(error!))
                        return
                    }
                    let paymentOptionSelection = SavedPaymentMethodsSheet.PaymentOptionSelection.savedPaymentMethod(paymentMethod)
                    self.setSelectablePaymentMethodAndClose(paymentOptionSelection: paymentOptionSelection)
                }
            }
        }
    }

    // MARK: Helpers
    func configureEditSavedPaymentMethodsButton() {
        if savedPaymentOptionsViewController.isRemovingPaymentMethods {
            navigationBar.additionalButton.setTitle(UIButton.doneButtonTitle, for: .normal)
            actionButton.update(state: .disabled)
        } else {
            actionButton.update(state: .enabled)
            navigationBar.additionalButton.setTitle(UIButton.editButtonTitle, for: .normal)
        }
        navigationBar.additionalButton.accessibilityIdentifier = "edit_saved_button"
        navigationBar.additionalButton.titleLabel?.adjustsFontForContentSizeCategory = true
        navigationBar.additionalButton.addTarget(
            self, action: #selector(didSelectEditSavedPaymentMethodsButton), for: .touchUpInside)
    }

    private func setSelectablePaymentMethodAndClose(paymentOptionSelection: SavedPaymentMethodsSheet.PaymentOptionSelection) {
        if let setSelectedPaymentMethodOption = self.configuration.customerContext.setSelectedPaymentMethodOption {
            let persistablePaymentOption = paymentOptionSelection.persistablePaymentMethodOption()
            setSelectedPaymentMethodOption(persistablePaymentOption) { error in
                if let error = error {
                    self.savedPaymentMethodsSheetDelegate?.didFail(with: .setSelectedPaymentMethodOption(error))
                } else {
                    self.savedPaymentMethodsSheetDelegate?.didClose(with: paymentOptionSelection)
                    self.delegate?.savedPaymentMethodsViewControllerDidFinish(self)
                }
            }
        } else {
            self.savedPaymentMethodsSheetDelegate?.didClose(with: paymentOptionSelection)
            self.delegate?.savedPaymentMethodsViewControllerDidFinish(self)
        }
    }
    private func handleCancel() {
        self.savedPaymentMethodsSheetDelegate?.didCancel()
        delegate?.savedPaymentMethodsViewControllerDidCancel(self)
    }

    @objc
    func didSelectEditSavedPaymentMethodsButton() {
        savedPaymentOptionsViewController.isRemovingPaymentMethods.toggle()
        configureEditSavedPaymentMethodsButton()
    }
}

extension SavedPaymentMethodsViewController: BottomSheetContentViewController {
    var allowsDragToDismiss: Bool {
        return isDismissable
    }

    func didTapOrSwipeToDismiss() {
        if isDismissable {
            handleCancel()
        }
    }

    var requiresFullScreen: Bool {
        return false
    }
}

// MARK: - SheetNavigationBarDelegate
/// :nodoc:
extension SavedPaymentMethodsViewController: SheetNavigationBarDelegate {
    func sheetNavigationBarDidClose(_ sheetNavigationBar: SheetNavigationBar) {
        handleCancel()

        if savedPaymentOptionsViewController.isRemovingPaymentMethods {
            savedPaymentOptionsViewController.isRemovingPaymentMethods = false
            configureEditSavedPaymentMethodsButton()
        }

    }

    func sheetNavigationBarDidBack(_ sheetNavigationBar: SheetNavigationBar) {
        switch mode {
        case .addingNewWithSetupIntent, .addingNewPaymentMethodAttachToCustomer:
            error = nil
            mode = .selectingSaved
            updateUI()
        default:
            assertionFailure()
        }
    }
}
extension SavedPaymentMethodsViewController: SavedPaymentMethodsAddPaymentMethodViewControllerDelegate {
    func didUpdate(_ viewController: SavedPaymentMethodsAddPaymentMethodViewController) {
        //TODO
    }
//    func shouldOfferLinkSignup(_ viewController: AddPaymentMethodViewController) -> Bool {
//        return false
//    }
    func updateErrorLabel(for: Error?) {
        //TODO
    }
}

extension SavedPaymentMethodsViewController: SavedPaymentMethodsCollectionViewControllerDelegate {
    func didUpdateSelection(
        viewController: SavedPaymentMethodsCollectionViewController,
        paymentMethodSelection: SavedPaymentMethodsCollectionViewController.Selection) {
            // TODO: Add some boolean flag here to avoid making duplicate calls
            switch(paymentMethodSelection) {
            case .add:
                error = nil
                if let createSetupIntentHandler = self.configuration.createSetupIntentHandler {
                    mode =  .addingNewWithSetupIntent
                    if let intent = self.intent, !intent.isInTerminalState {
                        initAddPaymentMethodViewController(intent: intent)
                        self.updateUI()
                    } else {
                        createSetupIntentHandler({ result in
                            guard let clientSecret = result else {
                                self.savedPaymentMethodsSheetDelegate?.didFail(with: .setupIntentClientSecretInvalid)
                                return
                            }
                            self.fetchSetupIntent(clientSecret: clientSecret) { result in
                                switch(result) {
                                case .success(let stpSetupIntent):
                                    let setupIntent = Intent.setupIntent(stpSetupIntent)
                                    self.intent = setupIntent
                                    self.initAddPaymentMethodViewController(intent: setupIntent)
                                    
                                case .failure(let error):
                                    self.savedPaymentMethodsSheetDelegate?.didFail(with: .setupIntentFetchError(error))
                                }
                                self.updateUI()
                            }
                        })
                    }
                } else {
                    mode = .addingNewPaymentMethodAttachToCustomer
                    self.initAddPaymentMethodViewController(intent: nil)
                    self.updateUI()
                }
            case .saved(let paymentMethod):
                let paymentOptionSelection = SavedPaymentMethodsSheet.PaymentOptionSelection.savedPaymentMethod(paymentMethod)
                self.setSelectablePaymentMethodAndClose(paymentOptionSelection: paymentOptionSelection)
            case .applePay:
                let paymentOptionSelection = SavedPaymentMethodsSheet.PaymentOptionSelection.applePay()
                self.setSelectablePaymentMethodAndClose(paymentOptionSelection: paymentOptionSelection)
            }
        }
    private func initAddPaymentMethodViewController(intent: Intent?) {
        self.addPaymentMethodViewController = SavedPaymentMethodsAddPaymentMethodViewController(
            intent: intent,
            configuration: self.configuration,
            delegate: self
        )
    }
    func didSelectRemove(
        viewController: SavedPaymentMethodsCollectionViewController,
        paymentMethodSelection: SavedPaymentMethodsCollectionViewController.Selection) {
            guard case .saved(let paymentMethod) = paymentMethodSelection else {
                return
            }
            configuration.customerContext.detachPaymentMethod?(fromCustomer: paymentMethod, completion: { error in
                if let error = error {
                    self.savedPaymentMethodsSheetDelegate?.didFail(with: .detachPaymentMethod(error))
                    return
                }
                //let removedPaymentOption = SavedPaymentMethodsSheet.PaymentOptionSelection.savedPaymentMethod(paymentMethod)
                //self.savedPaymentMethodsSheetDelegate?.didDetachPaymentMethod(with: removedPaymentOption)
                self.configuration.customerContext.setSelectedPaymentMethodOption?(paymentOption: nil, completion: { error in
                    if let error = error {
                        self.savedPaymentMethodsSheetDelegate?.didFail(with: .setSelectedPaymentMethodOption(error))
                        // If this fails, we should keep going -- not a whole lot we can do here.
                    }
                    //TODO: Auto select next payment method available (but don't confirm it)
                })
                
            })
        }
}

