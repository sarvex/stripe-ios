//
//  SavedPaymentMethodSheetTestPlayground.swift
//  PaymentSheet Example
//
//  ⚠️🏗 This is a playground for internal Stripe engineers to help us test things, and isn't
//  an example of what you should do in a real app!
//  Note: Do not import Stripe using `@_spi(STP)` in production.
//  This exposes internal functionality which may cause unexpected behavior if used directly.

import Foundation
import Contacts
import PassKit
import StripePaymentSheet
import StripePaymentsUI
import SwiftUI
import UIKit

class SavedPaymentMethodSheetTestPlayground: UIViewController {
    static let endpointSelectorEndpoint = "https://stripe-mobile-payment-sheet-test-playground-v6.glitch.me/endpoints"
    static let defaultSavedPaymentMethodEndpoint = "https://pool-seen-sandal.glitch.me"
    //"https://stripe-mobile-payment-sheet-test-playground-v6.glitch.me/saved_payment_method"
    
    static var paymentSheetPlaygroundSettings: SavedPaymentMethodSheetPlaygroundSettings?
    
    // Configuration
    @IBOutlet weak var customerModeSelector: UISegmentedControl!
    @IBOutlet weak var shippingInfoSelector: UISegmentedControl!
    @IBOutlet weak var loadButton: UIButton!
    @IBOutlet weak var selectingSavedCustomHeaderTextField: UITextField!
    
    @IBOutlet weak var pmModeSelector: UISegmentedControl!
    @IBOutlet weak var applePaySelector: UISegmentedControl!
    @IBOutlet weak var selectPaymentMethodImage: UIImageView!
    @IBOutlet weak var selectPaymentMethodButton: UIButton!
    
    var savedPaymentMethodsSheet: SavedPaymentMethodsSheet?
    var paymentOptionSelection: SavedPaymentMethodsSheet.PaymentOptionSelection?
    
    enum CustomerMode: String, CaseIterable {
        case new
        case returning
    }
    
    enum PaymentMethodMode {
        case setupIntent
        case createAndAttach
    }
    
    enum ShippingMode {
        case on
        case onWithDefaults
        case off
    }
    
    var customerMode: CustomerMode {
        switch customerModeSelector.selectedSegmentIndex {
        case 0:
            return .new
        default:
            return .returning
        }
    }
    
    var paymentMethodMode: PaymentMethodMode {
        switch pmModeSelector.selectedSegmentIndex {
        case 0:
            return .setupIntent
        default:
            return .createAndAttach
        }
    }
    
    var backend: SavedPaymentMethodsBackend!
    
    var ephemeralKey: String?
    var customerId: String?
    var customerContext: STPCustomerContext?
    var savedPaymentMethodEndpoint: String = defaultSavedPaymentMethodEndpoint
    var appearance = PaymentSheet.Appearance.default
    
    func makeAlertController() -> UIAlertController {
        let alertController = UIAlertController(
            title: "Complete", message: "Completed", preferredStyle: .alert)
        let OKAction = UIAlertAction(title: "OK", style: .default) { (_) in
            alertController.dismiss(animated: true, completion: nil)
        }
        alertController.addAction(OKAction)
        return alertController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadButton.addTarget(self, action: #selector(load), for: .touchUpInside)
        
        selectPaymentMethodButton.isEnabled = false
        selectPaymentMethodButton.addTarget(
            self, action: #selector(didTapSelectPaymentMethodButton), for: .touchUpInside)
        
        if let paymentSheetPlaygroundSettings = SavedPaymentMethodSheetTestPlayground.paymentSheetPlaygroundSettings {
            loadSettingsFrom(settings: paymentSheetPlaygroundSettings)
        } else if let nsUserDefaultSettings = settingsFromDefaults() {
            loadSettingsFrom(settings: nsUserDefaultSettings)
            loadBackend()
        }
    }
    @objc
    func didTapSelectPaymentMethodButton() {
        savedPaymentMethodsSheet?.present(from: self, delegate: self)
    }
    
    func updateButtons() {
        // Update the payment method selection button
        if let paymentOption = self.paymentOptionSelection {
            self.selectPaymentMethodButton.setTitle(paymentOption.displayData().label, for: .normal)
            self.selectPaymentMethodButton.setTitleColor(.label, for: .normal)
            self.selectPaymentMethodImage.image = paymentOption.displayData().image
        } else {
            self.selectPaymentMethodButton.setTitle("Select", for: .normal)
            self.selectPaymentMethodButton.setTitleColor(.systemBlue, for: .normal)
            self.selectPaymentMethodImage.image = nil
        }
        self.selectPaymentMethodButton.setNeedsLayout()
    }
    
    @IBAction func didTapEndpointConfiguration(_ sender: Any) {
        // Stubbed out for now
        //        let endpointSelector = EndpointSelectorViewController(delegate: self,
        //                                                              endpointSelectorEndpoint: Self.endpointSelectorEndpoint,
        //                                                              currentCheckoutEndpoint: sav)
        //        let navController = UINavigationController(rootViewController: endpointSelector)
        //        self.navigationController?.present(navController, animated: true, completion: nil)
    }
    
    @IBAction func didTapResetConfig(_ sender: Any) {
        loadSettingsFrom(settings: SavedPaymentMethodSheetPlaygroundSettings.defaultValues())
    }
    
    @IBAction func appearanceButtonTapped(_ sender: Any) {
        if #available(iOS 14.0, *) {
            let vc = UIHostingController(rootView: AppearancePlaygroundView(appearance: appearance, doneAction: { updatedAppearance in
                self.appearance = updatedAppearance
                self.dismiss(animated: true, completion: nil)
            }))
            
            self.navigationController?.present(vc, animated: true, completion: nil)
        } else {
            let alert = UIAlertController(title: "Unavailable", message: "Appearance playground is only available in iOS 14+.", preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func walletModeConfiguration(customerId: String, ephemeralKey: String) -> SavedPaymentMethodsSheet.Configuration {
        let customerContext = STPCustomerContext(customerId: customerId, ephemeralKeySecret: ephemeralKey)
        self.customerContext = customerContext
        var configuration = SavedPaymentMethodsSheet.Configuration(customerContext: customerContext,
                                                                   createSetupIntentHandler: setupIntentHandler(customerId: customerId))
        configuration.applePay = applePayConfig()
        configuration.appearance = appearance
        configuration.returnURL = "payments-example://stripe-redirect"
        configuration.selectingSavedCustomHeaderText = selectingSavedCustomHeaderTextField.text
        
        return configuration
    }
    func setupIntentHandler(customerId: String) -> SavedPaymentMethodsSheet.Configuration.CreateSetupIntentHandlerCallback? {
        switch(paymentMethodMode) {
        case .setupIntent:
            return { completionBlock in
                self.backend.createSetupIntent(customerId: customerId,
                                               completion: completionBlock)
            }
        case .createAndAttach:
            return nil
        }
    }
    func applePayConfig() -> SavedPaymentMethodsSheet.ApplePayConfiguration? {
        switch(applePaySelector.selectedSegmentIndex) {
        case 0:
            return .init(merchantId: "com.foo.example", merchantCountryCode: "US")
        default:
            return nil
        }
    }
}

// MARK: - Backend

extension SavedPaymentMethodSheetTestPlayground {
    @objc
    func load() {
        serializeSettingsToNSUserDefaults()
        loadBackend()
    }
    func loadBackend() {
        selectPaymentMethodButton.isEnabled = false
        savedPaymentMethodsSheet = nil
        paymentOptionSelection = nil

        let customerType = customerMode == .new ? "new" : "returning"
        self.backend = SavedPaymentMethodsBackend(endpoint: savedPaymentMethodEndpoint)

        self.backend.loadBackendCustomerEphemeralKey(customerType: customerType) { result in
            guard let json = result,
                  let ephemeralKey = json["customerEphemeralKeySecret"], !ephemeralKey.isEmpty,
                  let customerId = json["customerId"], !customerId.isEmpty,
                  let publishableKey = json["publishableKey"] else {
                return
            }
            self.ephemeralKey = ephemeralKey
            self.customerId = customerId
            StripeAPI.defaultPublishableKey = publishableKey

            DispatchQueue.main.async {
                let walletModeConfiguration = self.walletModeConfiguration(customerId: customerId, ephemeralKey: ephemeralKey)
                self.savedPaymentMethodsSheet = SavedPaymentMethodsSheet(configuration: walletModeConfiguration)

                self.selectPaymentMethodButton.isEnabled = true

                self.customerContext?.retrievePaymentOptionSelection { selection, error in
                    self.paymentOptionSelection = selection
                    self.updateButtons()
                }
            }
        }
    }
}

extension SavedPaymentMethodSheetTestPlayground: SavedPaymentMethodsSheetDelegate {
    func didCloseWith(paymentOptionSelection: SavedPaymentMethodsSheet.PaymentOptionSelection?) {
        self.paymentOptionSelection = paymentOptionSelection
        self.updateButtons()
    }
    
    func didError(_ error: SavedPaymentMethodsSheetError) {
        switch(error) {
        case .setupIntentClientSecretInvalid:
            print("Intent invalid...")
        case .errorFetchingSavedPaymentMethods(let error):
            print("saved payment methods errored:\(error)")
        case .setupIntentFetchError(let error):
            print("fetching si errored: \(error)")
        default:
            print("something went wrong: \(error)")
        }
    }
    func didDetachPaymentMethod(paymentOptionSelection: SavedPaymentMethodsSheet.PaymentOptionSelection) {
        print("detached payment option: \(paymentOptionSelection.displayData().label)")
    }
}

struct SavedPaymentMethodSheetPlaygroundSettings: Codable {
    static let nsUserDefaultsKey = "savedPaymentMethodPlaygroundSettings"

    let customerModeSelectorValue: Int
    let paymentMethodModeSelectorValue: Int
    let applePaySelectorSelectorValue: Int
    let selectingSavedCustomHeaderText: String?
    let savedPaymentMethodEndpoint: String?

    static func defaultValues() -> SavedPaymentMethodSheetPlaygroundSettings {
        return SavedPaymentMethodSheetPlaygroundSettings(
            customerModeSelectorValue: 0,
            paymentMethodModeSelectorValue: 0,
            applePaySelectorSelectorValue: 0,
            selectingSavedCustomHeaderText: nil,
            savedPaymentMethodEndpoint: SavedPaymentMethodSheetTestPlayground.defaultSavedPaymentMethodEndpoint
        )
    }
}

// MARK: - EndpointSelectorViewControllerDelegate
extension SavedPaymentMethodSheetTestPlayground: EndpointSelectorViewControllerDelegate {
    func selected(endpoint: String) {
        savedPaymentMethodEndpoint = endpoint
        serializeSettingsToNSUserDefaults()
        loadBackend()
        self.navigationController?.dismiss(animated: true)

    }
    func cancelTapped() {
        self.navigationController?.dismiss(animated: true)
    }
}

// MARK: - Helpers

extension SavedPaymentMethodSheetTestPlayground {
    func serializeSettingsToNSUserDefaults() {
        let settings = SavedPaymentMethodSheetPlaygroundSettings(
            customerModeSelectorValue: customerModeSelector.selectedSegmentIndex,
            paymentMethodModeSelectorValue: pmModeSelector.selectedSegmentIndex,
            applePaySelectorSelectorValue: applePaySelector.selectedSegmentIndex,
            selectingSavedCustomHeaderText: selectingSavedCustomHeaderTextField.text,
            savedPaymentMethodEndpoint: savedPaymentMethodEndpoint
        )
        let data = try! JSONEncoder().encode(settings)
        UserDefaults.standard.set(data, forKey: SavedPaymentMethodSheetPlaygroundSettings.nsUserDefaultsKey)
    }

    func settingsFromDefaults() -> SavedPaymentMethodSheetPlaygroundSettings? {
        if let data = UserDefaults.standard.value(forKey: SavedPaymentMethodSheetPlaygroundSettings.nsUserDefaultsKey) as? Data {
            do {
                return try JSONDecoder().decode(SavedPaymentMethodSheetPlaygroundSettings.self, from: data)
            } catch {
                print("Unable to deserialize saved settings")
                UserDefaults.standard.removeObject(forKey: SavedPaymentMethodSheetPlaygroundSettings.nsUserDefaultsKey)
            }
        }
        return nil
    }

    func loadSettingsFrom(settings: SavedPaymentMethodSheetPlaygroundSettings) {
        customerModeSelector.selectedSegmentIndex = settings.customerModeSelectorValue
        pmModeSelector.selectedSegmentIndex = settings.paymentMethodModeSelectorValue
        applePaySelector.selectedSegmentIndex = settings.applePaySelectorSelectorValue
        selectingSavedCustomHeaderTextField.text = settings.selectingSavedCustomHeaderText
        savedPaymentMethodEndpoint = settings.savedPaymentMethodEndpoint ?? SavedPaymentMethodSheetTestPlayground.defaultSavedPaymentMethodEndpoint
    }
}


class SavedPaymentMethodsBackend {

    let endpoint: String
    var clientSecret: String?
    public init(endpoint: String) {
        self.endpoint = endpoint
    }

    func loadBackendCustomerEphemeralKey(customerType: String, completion: @escaping ([String:String]?) -> Void) {

        let body = [ "customer_type": customerType
        ] as [String: Any]

        let url = URL(string: "\(endpoint)/saved_payment_method")!
        let session = URLSession.shared

        let json = try! JSONSerialization.data(withJSONObject: body, options: [])
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = json
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-type")
        let task = session.dataTask(with: urlRequest) { data, response, error in
            guard
                error == nil,
                let data = data,
                let json = try? JSONDecoder().decode([String: String].self, from: data) else {
                print(error as Any)
                completion(nil)
                return
            }
            completion(json)
        }
        task.resume()
    }

    func createSetupIntent(customerId: String, completion: @escaping (String?) -> Void) {
        guard clientSecret == nil else {
            completion(clientSecret)
            return
        }
        let body = [ "customer_id": customerId,
        ] as [String: Any]
        let url = URL(string: "\(endpoint)/create_setup_intent")!
        let session = URLSession.shared

        let json = try! JSONSerialization.data(withJSONObject: body, options: [])
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = json
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-type")
        let task = session.dataTask(with: urlRequest) { data, response, error in
            guard
                error == nil,
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                print(error as Any)
                completion(nil)
                return
            }
            guard let secret = json["client_secret"] as? String else {
                completion(nil)
                return
            }
            self.clientSecret = secret
            completion(secret)
        }
        task.resume()
    }
}
