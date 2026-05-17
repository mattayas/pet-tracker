"use client";

import { use, useState, useEffect } from "react";
import { supabase } from "../../../utils/supabase";

// 1. Simple dictionary for translations
const translations = {
  en: {
    title: "Pet Found!",
    foundPrefix: "You found",
    foundSuffix: "!",
    unknownPet: "this pet",
    btnIdle: "📍 Send my location to the owner",
    loading: "Getting location and sending...",
    success: "✅ Location sent successfully! The owner has been notified. Thank you!",
    errorLoc: "Geolocation is not supported or access was denied.",
    errorSend: "❌ An error occurred.",
    retry: "Try again",
    notFound: "This pet is not registered in our system."
  },
  fr: {
    title: "Animal trouvé !",
    foundPrefix: "Vous avez trouvé",
    foundSuffix: " !",
    unknownPet: "ce compagnon",
    btnIdle: "📍 Envoyer ma position au propriétaire",
    loading: "Localisation et envoi en cours...",
    success: "✅ Position envoyée avec succès ! Le propriétaire a été alerté. Merci !",
    errorLoc: "La géolocalisation n'est pas supportée ou l'accès a été refusé.",
    errorSend: "❌ Une erreur est survenue.",
    retry: "Réessayer",
    notFound: "Cet animal n'est pas enregistré dans notre système."
  }
};

type LangKey = keyof typeof translations;

export default function ScanPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);

  // States
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [petName, setPetName] = useState<string | null>(null);
  const [isValidPet, setIsValidPet] = useState<boolean | null>(null); // null = loading, true = exists, false = 404
  const [lang, setLang] = useState<LangKey>("en"); // Default to English

  // Fetch pet data and detect browser language on mount
  useEffect(() => {
    // Detect browser language (e.g., 'fr-FR' -> 'fr')
    const browserLang = navigator.language.split('-')[0] as LangKey;
    if (translations[browserLang]) {
      setLang(browserLang);
    }

    const fetchPetName = async () => {
      const { data, error } = await supabase
        .from("pets")
        .select("name")
        .eq("id", id)
        .single();

      if (error || !data) {
        setIsValidPet(false); // Pet not found in database
      } else {
        setPetName(data.name);
        setIsValidPet(true);
      }
    };

    fetchPetName();
  }, [id]);

  const t = translations[lang];

  const handleScan = () => {
    setStatus("loading");

    // Check if Geolocation API is available
    if (!navigator.geolocation) {
      alert(t.errorLoc);
      setStatus("error");
      return;
    }

    // Request GPS coordinates
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const { latitude, longitude } = position.coords;

        // Insert scan record into Supabase
        const { error } = await supabase
          .from("scans")
          .insert({
            pet_id: id,
            latitude: latitude,
            longitude: longitude,
          });

        if (error) {
          console.error("Insert error:", error.message);
          setStatus("error");
        } else {
          setStatus("success");
        }
      },
      (error) => {
        console.error("GPS error:", error.message);
        alert(t.errorLoc);
        setStatus("error");
      }
    );
  };

  // UI: Show a loading state while checking the database
  if (isValidPet === null) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-gray-50">
        <div className="animate-pulse w-8 h-8 rounded-full bg-blue-500"></div>
      </main>
    );
  }

  // UI: Show 404 state if pet ID is invalid
  if (isValidPet === false) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-gray-50 p-4">
        <div className="max-w-md w-full bg-white rounded-xl shadow-md p-6 text-center text-red-600">
          ⚠️ {t.notFound}
        </div>
      </main>
    );
  }

  // UI: Main App
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-50 p-4">
      <div className="max-w-md w-full bg-white rounded-xl shadow-md overflow-hidden p-6 text-center">
        <h1 className="text-2xl font-bold text-gray-900 mb-4">
          {t.title}
        </h1>

        <p className="text-gray-600 mb-8 text-lg">
          {t.foundPrefix} <span className="font-bold text-blue-600">{petName || t.unknownPet}</span>{t.foundSuffix}
        </p>

        {status === "idle" && (
          <button
            onClick={handleScan}
            className="w-full bg-red-500 hover:bg-red-600 text-white font-bold py-3 px-4 rounded-lg transition-colors shadow-lg"
          >
            {t.btnIdle}
          </button>
        )}

        {status === "loading" && (
          <div className="text-blue-500 font-semibold animate-pulse">
            {t.loading}
          </div>
        )}

        {status === "success" && (
          <div className="p-4 bg-green-100 text-green-700 rounded-lg font-semibold">
            {t.success}
          </div>
        )}

        {status === "error" && (
          <div className="p-4 bg-red-100 text-red-700 rounded-lg mb-4">
            {t.errorSend}
            <button
              onClick={() => setStatus("idle")}
              className="block w-full mt-3 text-sm underline"
            >
              {t.retry}
            </button>
          </div>
        )}
      </div>
    </main>
  );
}
