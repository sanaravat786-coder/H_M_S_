import React, { useState, useEffect, useRef } from 'react';
import { AnimatePresence } from 'framer-motion';
import { Search, X, Loader } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useDebounce } from '../../hooks/useDebounce';
import GlobalSearchResults from './GlobalSearchResults';
import toast from 'react-hot-toast';

const GlobalSearch = () => {
    const [searchTerm, setSearchTerm] = useState('');
    const [results, setResults] = useState(null);
    const [loading, setLoading] = useState(false);
    const [isFocused, setIsFocused] = useState(false);
    const debouncedSearchTerm = useDebounce(searchTerm, 300);
    const searchContainerRef = useRef(null);

    useEffect(() => {
        const handleClickOutside = (event) => {
            if (searchContainerRef.current && !searchContainerRef.current.contains(event.target)) {
                setIsFocused(false);
            }
        };
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

    useEffect(() => {
        if (debouncedSearchTerm.trim().length > 1) {
            setLoading(true);
            const performSearch = async () => {
                const { data, error } = await supabase.rpc('universal_search', {
                    p_search_term: debouncedSearchTerm.trim(),
                });

                if (error) {
                    toast.error(`Search failed: ${error.message}`);
                    setResults(null);
                } else {
                    setResults(data);
                }
                setLoading(false);
            };
            performSearch();
        } else {
            setResults(null);
            setLoading(false);
        }
    }, [debouncedSearchTerm]);

    const handleClear = () => {
        setSearchTerm('');
        setResults(null);
    };

    const handleCloseResults = () => {
        setIsFocused(false);
    };

    return (
        <div ref={searchContainerRef} className="relative w-full max-w-md">
            <div className="relative">
                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                    <Search className="h-5 w-5 text-base-content-secondary dark:text-dark-base-content-secondary" />
                </div>
                <input
                    type="text"
                    placeholder="Search students, rooms..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    onFocus={() => setIsFocused(true)}
                    className="block w-full rounded-lg border-transparent bg-base-200 dark:bg-dark-base-300 text-base-content dark:text-dark-base-content pl-10 pr-10 py-2.5 focus:border-primary dark:focus:border-dark-primary focus:ring-primary dark:focus:ring-dark-primary transition-colors sm:text-sm"
                />
                <div className="absolute inset-y-0 right-0 flex items-center pr-3">
                    {loading ? (
                        <Loader className="h-5 w-5 animate-spin text-base-content-secondary" />
                    ) : searchTerm && (
                        <button onClick={handleClear} className="text-base-content-secondary hover:text-base-content">
                            <X className="h-5 w-5" />
                        </button>
                    )}
                </div>
            </div>
            <AnimatePresence>
                {isFocused && (searchTerm.length > 1 || loading) && (
                    <GlobalSearchResults 
                        results={results} 
                        loading={loading} 
                        term={debouncedSearchTerm}
                        onClose={handleCloseResults}
                    />
                )}
            </AnimatePresence>
        </div>
    );
};

export default GlobalSearch;
