//
//  SavedPaymentMethodsSheetDelegate.swift
//  StripePaymentSheet
//

public protocol SavedPaymentMethodsSheetDelegate: AnyObject {
    func didClose(with paymentOptionSelection: SavedPaymentMethodsSheet.PaymentOptionSelection?)
    func didCancel()
    func didFail(with error: SavedPaymentMethodsSheetError)
}
