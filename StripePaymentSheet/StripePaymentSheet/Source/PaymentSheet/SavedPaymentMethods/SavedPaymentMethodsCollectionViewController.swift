//
//  SavedPaymentMethodsCollectionViewController.swift
//  StripePaymentSheet
//

import Foundation
import UIKit

@_spi(STP) import StripeCore
@_spi(STP) import StripePayments
@_spi(STP) import StripeUICore
@_spi(STP) import StripePaymentsUI

protocol SavedPaymentMethodsCollectionViewControllerDelegate: AnyObject {
    func didUpdateSelection(
        viewController: SavedPaymentMethodsCollectionViewController,
        paymentMethodSelection: SavedPaymentMethodsCollectionViewController.Selection)
    func didSelectRemove(
        viewController: SavedPaymentMethodsCollectionViewController,
        paymentMethodSelection: SavedPaymentMethodsCollectionViewController.Selection)
}
/*
 This class is largely a copy of SavedPaymentOptionsViewController, however a couple of exceptions
  - Removes link support
  - Does not save the selected payment method to the local device settings
  - Fetches customerId using the underlying backing STPCustomerContext
 */

/// For internal SDK use only
@objc(STP_Internal_SavedPaymentMethodsCollectionViewController)
class SavedPaymentMethodsCollectionViewController: UIViewController {
    // MARK: - Types
    // TODO (cleanup) Replace this with didSelectX delegate methods. Turn this into a private ViewModel class
    /**
     Represents the payment method the user has selected
     */
    enum Selection {
        case applePay
        case saved(paymentMethod: STPPaymentMethod)
        case add

        static func ==(lhs: Selection, rhs: PersistablePaymentMethodOption?) -> Bool {
            switch lhs {
            case .applePay:
                return rhs == .applePay
            case .saved(let paymentMethod):
                return paymentMethod.stripeId == rhs?.value
            case .add:
                return false
            }
        }
        func toSavedPaymentOptionsViewControllerSelection() -> SavedPaymentOptionsViewController.Selection {
            switch(self) {
            case .applePay:
                return .applePay
            case .add:
                return .add
            case .saved(let paymentMethod):
                return .saved(paymentMethod: paymentMethod)
            }
        }
    }

    struct Configuration {
        let showApplePay: Bool

        enum AutoSelectDefaultBehavior {
            /// will only autoselect default has been stored locally
            case onlyIfMatched
            /// will try to use locally stored default, or revert to first available
            case defaultFirst
            /// No auto selection
            case none
        }

        let autoSelectDefaultBehavior: AutoSelectDefaultBehavior
    }

    var hasRemovablePaymentMethods: Bool {
        return (
            !savedPaymentMethods.isEmpty
        )
    }

    var isRemovingPaymentMethods: Bool {
        get {
            return collectionView.isRemovingPaymentMethods
        }
        set {
            collectionView.isRemovingPaymentMethods = newValue
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
            if !collectionView.isRemovingPaymentMethods {
                // re-select
                collectionView.selectItem(
                    at: selectedIndexPath,
                    animated: false,
                    scrollPosition: []
                )
            }
        }
    }
    var bottomNoticeAttributedString: NSAttributedString? {
        if case .saved(let paymentMethod) = selectedPaymentOption {
            if paymentMethod.usBankAccount != nil {
                return USBankAccountPaymentMethodElement.attributedMandateTextSavedPaymentMethod(theme: appearance.asElementsTheme)
            }
        }
        return nil
    }

    // MARK: - Internal Properties
    let configuration: Configuration
    let savedPaymentMethodsConfiguration: SavedPaymentMethodsSheet.Configuration

    var selectedPaymentOption: PaymentOption? {
        guard let index = selectedViewModelIndex else {
            return nil
        }

        switch viewModels[index] {
        case .add:
            return nil
        case .applePay:
            return .applePay
        case let .saved(paymentMethod):
            return .saved(paymentMethod: paymentMethod)
        }
    }
    var savedPaymentMethods: [STPPaymentMethod] {
        didSet {
            updateUI()
        }
    }
    /// Whether or not there are any payment options we can show
    /// i.e. Are there any cells besides the Add cell?
    var hasPaymentOptions: Bool {
        return viewModels.contains {
            if case .add = $0 {
                return false
            }
            return true
        }
    }
    weak var delegate: SavedPaymentMethodsCollectionViewControllerDelegate?
    var appearance = PaymentSheet.Appearance.default

    // MARK: - Private Properties
    private var selectedViewModelIndex: Int?
    private var viewModels: [Selection] = []

    private var selectedIndexPath: IndexPath? {
        guard
            let index = selectedViewModelIndex,
            index < viewModels.count,
            selectedPaymentOption != nil
        else {
            return nil
        }

        return IndexPath(item: index, section: 0)
    }

    // MARK: - Views
    private lazy var collectionView: SavedPaymentMethodCollectionView = {
        let collectionView = SavedPaymentMethodCollectionView(appearance: appearance)
        collectionView.delegate = self
        collectionView.dataSource = self
        return collectionView
    }()

    // MARK: - Inits
    required init(
        savedPaymentMethods: [STPPaymentMethod],
        savedPaymentMethodsConfiguration: SavedPaymentMethodsSheet.Configuration,
        configuration: Configuration,
        appearance: PaymentSheet.Appearance,
        delegate: SavedPaymentMethodsCollectionViewControllerDelegate? = nil
    ) {
        self.savedPaymentMethods = savedPaymentMethods
        self.savedPaymentMethodsConfiguration = savedPaymentMethodsConfiguration
        self.configuration = configuration
        self.appearance = appearance
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
        updateUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        [collectionView].forEach({
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        })

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateUI()
    }

    // MARK: - Private methods
    private func updateUI() {
        if let retrieveLastSelectedPaymentMethodID = self.savedPaymentMethodsConfiguration.customerContext.retrieveLastSelectedPaymentMethodOption {
            retrieveLastSelectedPaymentMethodID { type, id, error in
                guard error == nil,
                      let defaultPaymentMethod = PersistablePaymentMethodOption(type: type, id: id) else {
                    self.updateUI(defaultPaymentMethod: nil)
                    return
                }
                self.updateUI(defaultPaymentMethod: defaultPaymentMethod)//DefaultPaymentMethodStore.PaymentMethodIdentifier(value: paymentMethodOptionIdentifier))
            }
        } else {
            self.updateUI(defaultPaymentMethod: nil)
        }
    }
    
    private func updateUI(defaultPaymentMethod: PersistablePaymentMethodOption?) {
        DispatchQueue.main.async {
            // Move default to front
            var savedPaymentMethods = self.savedPaymentMethods
            if let defaultPMIndex = savedPaymentMethods.firstIndex(where: {
                $0.stripeId == defaultPaymentMethod?.value
            }) {
                let defaultPM = savedPaymentMethods.remove(at: defaultPMIndex)
                savedPaymentMethods.insert(defaultPM, at: 0)
            }
            
            // Transform saved PaymentMethods into ViewModels
            let savedPMViewModels = savedPaymentMethods.compactMap { paymentMethod in
                return Selection.saved(paymentMethod: paymentMethod)
            }
            
            self.viewModels =
            [.add]
            + (self.configuration.showApplePay ? [.applePay] : [])
            + savedPMViewModels
            
            if self.configuration.autoSelectDefaultBehavior != .none {
                // Select default
                self.selectedViewModelIndex = self.viewModels.firstIndex(where: { $0 == defaultPaymentMethod })
                ?? (self.configuration.autoSelectDefaultBehavior == .defaultFirst ? 1 : nil)
            }
            
            self.collectionView.reloadData()
            self.collectionView.selectItem(at: self.selectedIndexPath, animated: false, scrollPosition: [])
            self.collectionView.scrollRectToVisible(CGRectZero, animated: false)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let selectedIndexPath = collectionView.indexPathsForSelectedItems?.first else {
            return
        }
        // For some reason, the selected cell loses its selected appearance
        collectionView.selectItem(at: selectedIndexPath, animated: false, scrollPosition: .bottom)
    }

    func unselectPaymentMethod() {
        guard let selectedIndexPath = selectedIndexPath else {
            return
        }
        selectedViewModelIndex = nil
        collectionView.deselectItem(at: selectedIndexPath, animated: true)
        collectionView.reloadItems(at: [selectedIndexPath])
    }
}

// MARK: - UICollectionView
/// :nodoc:
extension SavedPaymentMethodsCollectionViewController: UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
        -> Int
    {
        return viewModels.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let viewModel = viewModels[indexPath.item]
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SavedPaymentMethodCollectionView.PaymentOptionCell
                    .reuseIdentifier, for: indexPath)
                as? SavedPaymentMethodCollectionView.PaymentOptionCell
        else {
            assertionFailure()
            return UICollectionViewCell()
        }

        cell.setViewModel(viewModel.toSavedPaymentOptionsViewControllerSelection())
        cell.delegate = self
        cell.isRemovingPaymentMethods = self.collectionView.isRemovingPaymentMethods
        cell.appearance = appearance

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath)
        -> Bool
    {
        guard !self.collectionView.isRemovingPaymentMethods else {
            return false
        }
        let viewModel = viewModels[indexPath.item]
        if case .add = viewModel {
            delegate?.didUpdateSelection(viewController: self, paymentMethodSelection: viewModel)
            return false
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedViewModelIndex = indexPath.item
        let viewModel = viewModels[indexPath.item]

        // For wallet mode, I don't think we need to be setting the default --
        // we can call the delegate, and just return the payment method instead
        delegate?.didUpdateSelection(viewController: self, paymentMethodSelection: viewModel)
    }
}

// MARK: - PaymentOptionCellDelegate
/// :nodoc:
extension SavedPaymentMethodsCollectionViewController: PaymentOptionCellDelegate {
    func paymentOptionCellDidSelectRemove(
        _ paymentOptionCell: SavedPaymentMethodCollectionView.PaymentOptionCell
    ) {
        guard let indexPath = collectionView.indexPath(for: paymentOptionCell),
              case .saved(let paymentMethod) = viewModels[indexPath.row]
        else {
            assertionFailure()
            return
        }
        let viewModel = viewModels[indexPath.row]
        let alert = UIAlertAction(
            title: String.Localized.remove, style: .destructive
        ) { (_) in
            self.viewModels.remove(at: indexPath.row)
            // the deletion needs to be in a performBatchUpdates so we make sure it is completed
            // before potentially leaving edit mode (which triggers a reload that may collide with
            // this deletion)
            self.collectionView.performBatchUpdates {
                self.collectionView.deleteItems(at: [indexPath])
            } completion: { _ in
                self.savedPaymentMethods.removeAll(where: {
                    $0.stripeId == paymentMethod.stripeId
                })

                if let index = self.selectedViewModelIndex {
                    if indexPath.row == index {
                        self.selectedViewModelIndex = min(1, self.viewModels.count - 1)
                    } else if indexPath.row < index {
                        self.selectedViewModelIndex = index - 1
                    }
                }

                self.delegate?.didSelectRemove(
                    viewController: self,
                    paymentMethodSelection: viewModel
                )
            }
        }
        let cancel = UIAlertAction(
            title: String.Localized.cancel,
            style: .cancel, handler: nil
        )

        let alertController = UIAlertController(
            title: paymentMethod.removalMessage.title,
            message: paymentMethod.removalMessage.message,
            preferredStyle: .alert
        )

        alertController.addAction(cancel)
        alertController.addAction(alert)
        present(alertController, animated: true, completion: nil)
    }
}
