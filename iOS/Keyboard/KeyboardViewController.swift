import UIKit
import WhisperShared

final class KeyboardViewController: UIInputViewController {
    private let audioCapture = AudioCapture()
    private let transcriber = Transcriber()
    private var isRecording = false
    private var isBusy = false

    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        SharedStorage.appGroupID = "group.com.quincy.whisper"
        setupUI()
        setupCallbacks()
        requestPermissionsAndLoad()
    }

    private func setupUI() {
        view.backgroundColor = .clear

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.4, green: 0.2, blue: 0.75, alpha: 1).cgColor,
            UIColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = CGRect(x: 0, y: 0, width: 600, height: 140)
        container.layer.insertSublayer(gradient, at: 0)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.text = "Loading model"

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle("Magic Wand", for: .normal)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        actionButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        actionButton.layer.cornerRadius = 12
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.text = "Tap to dictate. Text inserts at the cursor."

        container.addSubview(statusLabel)
        container.addSubview(actionButton)
        container.addSubview(hintLabel)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            statusLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            actionButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            actionButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            actionButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            actionButton.heightAnchor.constraint(equalToConstant: 44),

            hintLabel.topAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 10),
            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            hintLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
    }

    private func setupCallbacks() {
        audioCapture.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.statusLabel.text = error
            }
        }

        transcriber.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.statusLabel.text = error
            }
        }

        transcriber.onModelLoaded = { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.statusLabel.text = "Ready"
                } else {
                    self?.statusLabel.text = error ?? "Model error"
                }
            }
        }
    }

    private func requestPermissionsAndLoad() {
        Task {
            let granted = await audioCapture.requestPermission()
            DispatchQueue.main.async {
                if !granted {
                    self.statusLabel.text = "Mic permission denied"
                }
            }
            await transcriber.loadModel("tiny.en")
        }
    }

    @objc private func handleAction() {
        if isBusy { return }
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try audioCapture.start()
            isRecording = true
            statusLabel.text = "Listening"
            actionButton.setTitle("Stop", for: .normal)
        } catch {
            statusLabel.text = error.localizedDescription
        }
    }

    private func stopRecording() {
        isRecording = false
        isBusy = true
        statusLabel.text = "Processing"
        actionButton.setTitle("Magic Wand", for: .normal)

        let audio = audioCapture.stop()
        guard audio.count >= 8000 else {
            statusLabel.text = "Too short"
            isBusy = false
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard let payload = await transcriber.transcribe(audio) else {
                DispatchQueue.main.async {
                    self.statusLabel.text = "No speech detected"
                    self.isBusy = false
                }
                return
            }

            let finalText = CorrectionEngine.shared.apply(to: payload.text)
            DispatchQueue.main.async {
                self.textDocumentProxy.insertText(finalText)
                self.statusLabel.text = "Inserted"
                self.isBusy = false
            }
        }
    }
}
