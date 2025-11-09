import React, { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import Modal from '../ui/Modal';
import { Loader } from 'lucide-react';
import toast from 'react-hot-toast';

const EditProfileModal = ({ isOpen, onClose, profile, onProfileUpdate }) => {
    const [formData, setFormData] = useState({
        full_name: '',
        contact: '',
        course: ''
    });
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (profile) {
            setFormData({
                full_name: profile.full_name || '',
                contact: profile.contact || '',
                course: profile.course || ''
            });
        }
    }, [profile]);

    const handleChange = (e) => {
        const { name, value } = e.target;
        setFormData(prev => ({ ...prev, [name]: value }));
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);

        const { error } = await supabase
            .from('profiles')
            .update({
                full_name: formData.full_name,
                contact: formData.contact,
                course: formData.course
            })
            .eq('id', profile.id);

        if (error) {
            toast.error(`Failed to update profile: ${error.message}`);
        } else {
            toast.success('Profile updated successfully!');
            onProfileUpdate();
            onClose();
        }
        setLoading(false);
    };

    return (
        <Modal title="Edit Profile" isOpen={isOpen} onClose={onClose}>
            <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                    <label htmlFor="full_name" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Full Name</label>
                    <input type="text" name="full_name" id="full_name" value={formData.full_name} onChange={handleChange} required className="mt-1 block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                </div>
                <div>
                    <label htmlFor="contact" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Contact Number</label>
                    <input type="tel" name="contact" id="contact" value={formData.contact} onChange={handleChange} required className="mt-1 block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                </div>
                {profile?.role === 'Student' && (
                    <div>
                        <label htmlFor="course" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Course</label>
                        <input type="text" name="course" id="course" value={formData.course} onChange={handleChange} required className="mt-1 block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                )}
                <div className="flex justify-end pt-4 space-x-3">
                    <button type="button" onClick={onClose} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-lg text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                    <button type="submit" disabled={loading} className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-lg text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50">
                        {loading ? <Loader className="animate-spin h-4 w-4 mr-2" /> : null}
                        Save Changes
                    </button>
                </div>
            </form>
        </Modal>
    );
};

export default EditProfileModal;
