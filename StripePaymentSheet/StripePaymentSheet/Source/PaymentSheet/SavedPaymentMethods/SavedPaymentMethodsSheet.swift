//
//  SavedPaymentMethodSheet.swift
//  StripePaymentSheet
//
//  Created by John Woo on 1/26/23.
//

import Foundation
import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripePayments
@_spi(STP) import StripePaymentsUI
@_spi(STP) import StripeUICore

@frozen public enum SavedPaymentMethodsSheetResult {
    /// The customer completed the payment or setup
    /// - Note: The payment may still be processing at this point; don't assume money has successfully moved.
    ///
    /// Your app should transition to a generic receipt view (e.g. a screen that displays "Your order is confirmed!"), and
    /// fulfill the order (e.g. ship the product to the customer) after receiving a successful payment event from Stripe -
    /// see https://stripe.com/docs/payments/handling-payment-events
    case completed(NSObject?)

    case canceled
    
    /// The attempt failed.
    /// - Parameter error: The error encountered by the customer. You can display its `localizedDescription` to the customer.
    case failed(error: Error)
}

public class SavedPaymentMethodsSheet {
    let configuration: SavedPaymentMethodsSheet.Configuration

    private var savedPaymentMethodsViewController: SavedPaymentMethodsViewController?

    private weak var savedPaymentMethodsSheetDelegate: SavedPaymentMethodsSheetDelegate?

    /// The STPPaymentHandler instance
    @available(iOSApplicationExtension, unavailable)
    @available(macCatalystApplicationExtension, unavailable)
    lazy var paymentHandler: STPPaymentHandler = { STPPaymentHandler(apiClient: configuration.apiClient, formSpecPaymentHandler: PaymentSheetFormSpecPaymentHandler()) }()

    /// The parent view controller to present
    @available(iOSApplicationExtension, unavailable)
    @available(macCatalystApplicationExtension, unavailable)
    lazy var bottomSheetViewController: BottomSheetViewController = {
        let isTestMode = configuration.apiClient.isTestmode
        let loadingViewController = LoadingViewController(
            delegate: self,
            appearance: configuration.appearance,
            isTestMode: isTestMode
        )

        let vc = BottomSheetViewController(
            contentViewController: loadingViewController,
            appearance: configuration.appearance,
            isTestMode: isTestMode,
            didCancelNative3DS2: { [weak self] in
                self?.paymentHandler.cancel3DS2ChallengeFlow()
            }
        )

        if #available(iOS 13.0, *) {
            configuration.style.configure(vc)
        }
        return vc
    }()

    public init(configuration: SavedPaymentMethodsSheet.Configuration) {
        self.configuration = configuration
    }

    @available(iOSApplicationExtension, unavailable)
    @available(macCatalystApplicationExtension, unavailable)
    public func present(from presentingViewController: UIViewController, delegate: SavedPaymentMethodsSheetDelegate? = nil) {
        self.savedPaymentMethodsSheetDelegate = delegate
        // Retain self when being presented, it is not guarnteed that SavedPaymentMethodsSheet instance
        // will be retained by caller
        let completion: () -> Void = {
            if let presentingViewController = self.bottomSheetViewController.presentingViewController {
                // Calling `dismiss()` on the presenting view controller causes
                // the bottom sheet and any presented view controller by
                // bottom sheet (i.e. Link) to be dismissed all at the same time.
                presentingViewController.dismiss(animated: true)
            }
            self.completion = nil
        }
        self.completion = completion

        guard presentingViewController.presentedViewController == nil else {
            assertionFailure("presentingViewController is already presenting a view controller")
            let error = SavedPaymentMethodsSheetError.unknown(
                debugDescription: "presentingViewController is already presenting a view controller"
            )
            delegate?.didFail(with: error)
            return
        }
        loadPaymentMethods() { result in
            switch(result) {
            case .success(let savedPaymentMethods):
                self.present(from: presentingViewController, savedPaymentMethods: savedPaymentMethods)
            case .failure(let error):
                delegate?.didFail(with: .errorFetchingSavedPaymentMethods(error))
                return
            }
        }
        presentingViewController.presentAsBottomSheet(bottomSheetViewController,
                                                      appearance: configuration.appearance)
    }

    @available(iOSApplicationExtension, unavailable)
    @available(macCatalystApplicationExtension, unavailable)
    func present(from presentingViewController: UIViewController,
                 savedPaymentMethods: [STPPaymentMethod]) {
        let loadSpecsPromise = Promise<Void>()
        AddressSpecProvider.shared.loadAddressSpecs {
            loadSpecsPromise.resolve(with: ())
        }
       
        loadSpecsPromise.observe { _ in
            DispatchQueue.main.async {
                let isApplePayEnabled = StripeAPI.deviceSupportsApplePay() && self.configuration.applePayEnabled
                let savedPaymentSheetVC = SavedPaymentMethodsViewController(savedPaymentMethods: savedPaymentMethods,
                                                                            configuration: self.configuration,
                                                                            isApplePayEnabled: isApplePayEnabled,
                                                                            savedPaymentMethodsSheetDelegate: self.savedPaymentMethodsSheetDelegate,
                                                                            delegate: self)
                self.bottomSheetViewController.contentStack = [savedPaymentSheetVC]
            }
        }
    }
    // MARK: - Internal Properties
    var completion: (() -> Void)?
}

extension SavedPaymentMethodsSheet {
    func loadPaymentMethods(completion: @escaping (Result<[STPPaymentMethod], SavedPaymentMethodsSheetError>) -> Void) {
        configuration.customerContext.listPaymentMethodsForCustomer {
            paymentMethods, error in
            guard let paymentMethods = paymentMethods, error == nil else {
                // TODO: Pass errors from the customerContext
                let error = PaymentSheetError.unknown(debugDescription: "Failed to retrieve PaymentMethods for the customer")
//                let error = error ?? PaymentSheetError.unknown(
//                    debugDescription: "Failed to retrieve PaymentMethods for the customer"
//                )
                completion(.failure(.errorFetchingSavedPaymentMethods(error)))
                return
            }
            let filteredPaymentMethods = paymentMethods.filter{ $0.type == .card }
            completion(.success(filteredPaymentMethods))
        }

    }

}

@available(iOSApplicationExtension, unavailable)
@available(macCatalystApplicationExtension, unavailable)
extension SavedPaymentMethodsSheet: SavedPaymentMethodsViewControllerDelegate {
    func savedPaymentMethodsViewControllerShouldConfirm(_ savedPaymentMethodsViewController: SavedPaymentMethodsViewController, with paymentOption: PaymentOption, completion: @escaping (SavedPaymentMethodsSheetResult) -> Void) {
        guard let intent = savedPaymentMethodsViewController.intent else {
            assert(false, "Payment intent not available")
            completion(.failed(error: SavedPaymentMethodsSheetError.unknown(debugDescription: "No payment intent available")))
        }
        let presentingViewController = savedPaymentMethodsViewController.presentingViewController

        let confirm: (@escaping (SavedPaymentMethodsSheetResult) -> Void) -> Void = { completion in
//            SavedPaymentMethodsSheet.confirm(
//                configuration: self.configuration,
//                authenticationContext: self.bottomSheetViewController,
//                intent: savedPaymentMethodsViewController.intent //paymentSheetViewController.intent,
//                paymentOption: paymentOption,
//                paymentHandler: self.paymentHandler)
//            { result in
//                if case let .failed(error) = result {
//                    self.mostRecentError = error
//                }
//                completion(result)
//            }
            self.confirmIntent(intent: intent, paymentOption: paymentOption) { result in
                if case let .failed(error) = result {
                    print(error)
//                    self.mostRecentError = error
                }
                completion(result)
            }
        }
        
        if case .applePay = paymentOption {
            savedPaymentMethodsViewController.dismiss(animated: true) {
                confirm { result in
                    if case .completed = result {
                        //TODO: Communicate back that they used apple pay and
                        // send back the PMid back to the caller --here?
                    } else {
                        presentingViewController?.presentAsBottomSheet(self.bottomSheetViewController, appearance: self.configuration.appearance)
                    }
                    completion(result)
                    
                }
            }
        } else {
            confirm { result in
                completion(result)
            }
        }
    }
    
    func savedPaymentMethodsViewControllerDidCancel(_ savedPaymentMethodsViewController: SavedPaymentMethodsViewController) {
        savedPaymentMethodsViewController.dismiss(animated: true) {
            self.completion?()
        }
    }

    func savedPaymentMethodsViewControllerDidFinish(_ savedPaymentMethodsViewController: SavedPaymentMethodsViewController) {
        savedPaymentMethodsViewController.dismiss(animated: true) {
            self.completion?()
        }
    }
}

extension SavedPaymentMethodsSheet: LoadingViewControllerDelegate {
    func shouldDismiss(_ loadingViewController: LoadingViewController) {
        loadingViewController.dismiss(animated: true) {
            self.completion?()
        }
    }
}

extension STPCustomerContext {
    /// Returns the selected Payment Option for this customer context.
    /// You can use this to obtain the selected payment method without loading the SavedPaymentMethodsSheet.
    public func retrievePaymentOptionSelection(
        completion: @escaping (SavedPaymentMethodsSheet.PaymentOptionSelection?, Error?) -> Void
    ) {
        self.listPaymentMethodsForCustomer { paymentMethods, error in
            guard let paymentMethods = paymentMethods, error == nil else {
                // TODO: Pass errors from the customerContext
                let error = PaymentSheetError.unknown(debugDescription: "Failed to retrieve PaymentMethods for the customer")
                completion(nil, error)
                return
            }
            self.retrieveSelectedPaymentMethodOption { paymentMethodOption, error in
                guard error == nil,
                let paymentMethodOption = paymentMethodOption else {
                    completion(nil, error)
                    return
                }
                switch(paymentMethodOption.type) {
                case .applePay:
                    completion(SavedPaymentMethodsSheet.PaymentOptionSelection.applePay(), nil)
                case .stripe:
                    guard let stripePaymentMethod = paymentMethodOption.stripePaymentMethodId,
                        let matchingPaymentMethod = paymentMethods.first(where:{ $0.stripeId == stripePaymentMethod }) else {
                        completion(nil, nil)
                        return
                    }
                    completion(SavedPaymentMethodsSheet.PaymentOptionSelection.savedPaymentMethod(matchingPaymentMethod), nil)
                default:
                    completion(nil, nil)
                }
            }
        }
    }
}
