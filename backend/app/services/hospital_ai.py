"""Trainable operational hospital suitability ranker.

This is an engineering prototype, not a clinically validated model. Its job is
only to rank hospitals using observable operational signals returned by the live
hospital discovery service plus route ETA/distance.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class HospitalFeatures:
    condition_fit: float
    emergency_service: float
    bed_metadata: float
    specialty_fit: float
    eta_score: float
    distance_score: float
    data_confidence: float
    urgency: float


class HospitalSuitabilityModel:
    VERSION = "rescupath-live-hospital-ranker-v2"

    def __init__(self) -> None:
        self.weights, self.bias = self._train()

    @staticmethod
    def _sigmoid(value: float) -> float:
        value = max(-30.0, min(30.0, value))
        return 1.0 / (1.0 + math.exp(-value))

    def _train(self) -> tuple[list[float], float]:
        """Train a small logistic model over synthetic operational labels."""
        rows: list[tuple[list[float], int]] = []

        for condition_fit in (0.2, 0.45, 0.7, 1.0):
            for emergency_service in (0.0, 1.0):
                for bed_metadata in (0.0, 0.5, 1.0):
                    for specialty_fit in (0.2, 0.6, 1.0):
                        for eta_score in (0.2, 0.5, 0.8, 1.0):
                            for distance_score in (0.2, 0.5, 0.8, 1.0):
                                for data_confidence in (0.3, 0.7, 1.0):
                                    for urgency in (0.25, 0.6, 1.0):
                                        x = [
                                            condition_fit,
                                            emergency_service,
                                            bed_metadata,
                                            specialty_fit,
                                            eta_score,
                                            distance_score,
                                            data_confidence,
                                            urgency,
                                        ]

                                        utility = (
                                            0.27 * condition_fit
                                            + 0.12 * emergency_service
                                            + 0.06 * bed_metadata
                                            + 0.12 * specialty_fit
                                            + (0.20 + 0.08 * urgency) * eta_score
                                            + (0.10 - 0.04 * urgency) * distance_score
                                            + 0.08 * data_confidence
                                        )
                                        label = 1 if utility >= 0.61 else 0
                                        rows.append((x, label))

        weights = [0.0] * 8
        bias = -1.0
        learning_rate = 0.15

        for _ in range(160):
            grad_w = [0.0] * 8
            grad_b = 0.0

            for x, y in rows:
                z = bias + sum(w * value for w, value in zip(weights, x))
                probability = self._sigmoid(z)
                error = probability - y
                for i, value in enumerate(x):
                    grad_w[i] += error * value
                grad_b += error

            scale = 1.0 / len(rows)
            for i in range(8):
                weights[i] -= learning_rate * grad_w[i] * scale
            bias -= learning_rate * grad_b * scale

        return weights, bias

    def predict(self, features: HospitalFeatures) -> float:
        vector = [
            features.condition_fit,
            features.emergency_service,
            features.bed_metadata,
            features.specialty_fit,
            features.eta_score,
            features.distance_score,
            features.data_confidence,
            features.urgency,
        ]

        probability = self._sigmoid(
            self.bias + sum(w * value for w, value in zip(self.weights, vector))
        )
        return round(probability * 100.0, 2)


MODEL = HospitalSuitabilityModel()
