import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import PageHeader from '../components/ui/PageHeader';
import Modal from '../components/ui/Modal';
import EmptyState from '../components/ui/EmptyState';
import toast from 'react-hot-toast';
import { Loader, Trash2, Megaphone } from 'lucide-react';

const containerVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1, transition: { staggerChildren: 0.1 } }
};

const itemVariants = {
    hidden: { opacity: 0, y: 20 },
    visible: { opacity: 1, y: 0 }
};

const NoticesPage = () => {
    const [notices, setNotices] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [formLoading, setFormLoading] = useState(false);
    const { user } = useAuth();
    const userRole = user?.user_metadata?.role;
    const canManage = userRole === 'Admin' || userRole === 'Staff';

    const fetchNotices = async () => {
        setLoading(true);
        try {
            const { data, error } = await supabase
                .from('notices')
                .select('*, profiles(full_name)')
                .order('created_at', { ascending: false });

            if (error) throw error;
            setNotices(data || []);
        } catch (error) {
            toast.error(`Failed to fetch notices: ${error.message}`);
            setNotices([]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchNotices();
    }, []);

    const handleDelete = async (noticeId) => {
        if (window.confirm('Are you sure you want to delete this notice?')) {
            const { error } = await supabase.from('notices').delete().eq('id', noticeId);
            if (error) {
                toast.error(error.message);
            } else {
                toast.success('Notice deleted.');
                fetchNotices();
            }
        }
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setFormLoading(true);
        const formData = new FormData(e.target);
        const noticeData = {
            title: formData.get('title'),
            message: formData.get('message'),
            audience: formData.get('audience'),
            created_by: user.id,
        };

        const { error } = await supabase.from('notices').insert([noticeData]);

        if (error) {
            toast.error(error.message);
        } else {
            toast.success('Notice published successfully!');
            fetchNotices();
            setIsModalOpen(false);
        }
        setFormLoading(false);
    };

    return (
        <>
            <PageHeader
                title="Notice Board"
                buttonText={canManage ? "Publish Notice" : null}
                onButtonClick={() => setIsModalOpen(true)}
            />
            {loading ? (
                <div className="flex justify-center items-center h-64">
                    <Loader className="animate-spin h-8 w-8 text-primary" />
                </div>
            ) : notices.length > 0 ? (
                <motion.div
                    className="space-y-6"
                    variants={containerVariants}
                    initial="hidden"
                    animate="visible"
                >
                    {notices.map((notice) => (
                        <motion.div
                            key={notice.id}
                            variants={itemVariants}
                            className="relative bg-base-100 dark:bg-dark-base-200 rounded-2xl shadow-lg p-6 transition-colors"
                        >
                            {canManage && (
                                <button
                                    onClick={() => handleDelete(notice.id)}
                                    className="absolute top-4 right-4 p-2 text-red-500/60 hover:text-red-500 hover:bg-red-500/10 rounded-full transition-colors"
                                    aria-label="Delete notice"
                                >
                                    <Trash2 className="w-5 h-5" />
                                </button>
                            )}
                            <h3 className="text-xl font-bold font-heading text-base-content dark:text-dark-base-content pr-12">{notice.title}</h3>
                            <div className="text-xs text-base-content-secondary dark:text-dark-base-content-secondary mt-1 mb-4">
                                <span>Published by {notice.profiles?.full_name || 'Admin'} on {new Date(notice.created_at).toLocaleDateString()}</span>
                                <span className="mx-2">|</span>
                                <span>Audience: <span className="font-semibold capitalize">{notice.audience}</span></span>
                            </div>
                            <p className="text-base-content-secondary dark:text-dark-base-content-secondary whitespace-pre-wrap">{notice.message}</p>
                        </motion.div>
                    ))}
                </motion.div>
            ) : (
                <div className="bg-base-100 dark:bg-dark-base-200 rounded-2xl shadow-lg">
                    <EmptyState
                        icon={<Megaphone className="w-full h-full" />}
                        title="No Notices Found"
                        message="Important announcements will appear here."
                    />
                </div>
            )}

            <Modal title="Publish New Notice" isOpen={isModalOpen} onClose={() => setIsModalOpen(false)}>
                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label htmlFor="title" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Title</label>
                        <input type="text" name="title" id="title" required className="mt-1 block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                    <div>
                        <label htmlFor="message" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Message</label>
                        <textarea name="message" id="message" rows="4" required className="mt-1 block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm"></textarea>
                    </div>
                    <div>
                        <label htmlFor="audience" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Audience</label>
                        <select id="audience" name="audience" defaultValue="all" required className="mt-1 block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm">
                            <option value="all">All</option>
                            <option value="students">Students Only</option>
                            <option value="staff">Staff Only</option>
                        </select>
                    </div>
                    <div className="flex justify-end pt-4 space-x-3">
                        <button type="button" onClick={() => setIsModalOpen(false)} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-lg text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                        <button type="submit" disabled={formLoading} className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-lg text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50">
                            {formLoading && <Loader className="animate-spin h-4 w-4 mr-2" />}
                            Publish Notice
                        </button>
                    </div>
                </form>
            </Modal>
        </>
    );
};

export default NoticesPage;
