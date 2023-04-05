//
//  SavedPaymentMethodsSheetConfiguration.swift
//  StripePaymentSheet
//

import Foundation
import UIKit
@_spi(STP) import StripePaymentsUI
@_spi(STP) import StripeUICore
@_spi(STP) import StripeCore

extension SavedPaymentMethodsSheet {

    public struct Configuration {
        public typealias CreateSetupIntentHandlerCallback = ((@escaping (String?) -> Void) -> Void)
               
        private var styleRawValue: Int = 0  // SheetStyle.automatic.rawValue
        /// The color styling to use for PaymentSheet UI
        /// Default value is SheetStyle.automatic
        /// @see SheetStyle
        @available(iOS 13.0, *)
        public var style: PaymentSheet.UserInterfaceStyle {  // stored properties can't be marked @available which is why this uses the styleRawValue private var
            get {
                return PaymentSheet.UserInterfaceStyle(rawValue: styleRawValue)!
            }
            set {
                styleRawValue = newValue.rawValue
            }
        }
        /// Describes the appearance of SavdPaymentMethodsSheet
        public var appearance = PaymentSheet.Appearance.default

        /// A URL that redirects back to your app that PaymentSheet can use to auto-dismiss
        /// web views used for additional authentication, e.g. 3DS2
        public var returnURL: String?
 
        /// The APIClient instance used to make requests to Stripe
        public var apiClient: STPAPIClient = STPAPIClient.shared

        public var applePayEnabled: Bool
        
        /// Configuration related to the Stripe Customer
        public var customerContext: STPBackendAPIAdapter

        /// Configuration for setting the text for the header
        public var selectingSavedCustomHeaderText: String?

        /// A block that provides a SetupIntent which, when confirmed, will attach a PaymentMethod to the current customer.
        /// Upon calling this, return a SetupIntent with the current customer set as the `customer`.
        /// If this is not set, the PaymentMethod will be attached directly to the customer instead.
        public var createSetupIntentHandler: CreateSetupIntentHandlerCallback?

        
        public init (customerContext: STPBackendAPIAdapter,
                     applePayEnabled: Bool,
                     createSetupIntentHandler: CreateSetupIntentHandlerCallback? = nil) {
            self.customerContext = customerContext
            self.createSetupIntentHandler = createSetupIntentHandler
            self.applePayEnabled = applePayEnabled
        }
    }
}

extension SavedPaymentMethodsSheet {
    public enum PaymentOptionSelection {
        
        public struct PaymentOptionDisplayData {
            public let image: UIImage
            public let label: String
        }
        case applePay(paymentOptionDisplayData: PaymentOptionDisplayData)
        case saved(paymentMethod: STPPaymentMethod, paymentOptionDisplayData: PaymentOptionDisplayData)
        case new(paymentMethod: STPPaymentMethod, paymentOptionDisplayData: PaymentOptionDisplayData)

        public static func savedPaymentMethod(_ paymentMethod: STPPaymentMethod) -> PaymentOptionSelection {
            let data = PaymentOptionDisplayData(image: paymentMethod.makeIcon(), label: paymentMethod.paymentSheetLabel)
            return .saved(paymentMethod: paymentMethod, paymentOptionDisplayData: data)
        }
        public static func newPaymentMethod(_ paymentMethod: STPPaymentMethod) -> PaymentOptionSelection {
            let data = PaymentOptionDisplayData(image: paymentMethod.makeIcon(), label: paymentMethod.paymentSheetLabel)
            return .new(paymentMethod: paymentMethod, paymentOptionDisplayData: data)
        }
        public static func applePay() -> PaymentOptionSelection {
            let displayData = SavedPaymentMethodsSheet.PaymentOptionSelection.PaymentOptionDisplayData(image: Image.apple_pay_mark.makeImage().withRenderingMode(.alwaysOriginal),
                                                                                                       label: String.Localized.apple_pay)
            return .applePay(paymentOptionDisplayData: displayData)
        }
        
        public func displayData() -> PaymentOptionDisplayData {
            switch(self) {
            case .applePay(let paymentOptionDisplayData):
                return paymentOptionDisplayData
            case .saved(_, let paymentOptionDisplayData):
                return paymentOptionDisplayData
            case .new(_, let paymentOptionDisplayData):
                return paymentOptionDisplayData
            }
        }
        
        func persistablePaymentMethodOption() -> PersistablePaymentMethodOption {
            switch(self) {
            case .applePay:
                return PersistablePaymentMethodOption.applePay()
            case .saved(let paymentMethod, _):
                return PersistablePaymentMethodOption.stripePaymentMethod(paymentMethod.stripeId)
            case .new(let paymentMethod, _):
                return PersistablePaymentMethodOption.stripePaymentMethod(paymentMethod.stripeId)
            }
        }
    }
}
