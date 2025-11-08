import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import PageHeader from '../components/ui/PageHeader';
import Modal from '../components/ui/Modal';
import EmptyState from '../components/ui/EmptyState';
import toast from 'react-hot-toast';
import { Loader, Edit, Trash2, Wrench } from 'lucide-react';
import { useAuth } from '../context/AuthContext';

const statusStyles = {
    Pending: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
    'In Progress': 'bg-blue-500/10 text-blue-600 dark:bg-blue-500/20 dark:text-blue-400',
    Resolved: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
};

const containerVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1, transition: { staggerChildren: 0.05 } }
};

const itemVariants = {
    hidden: { opacity: 0, y: 10 },
    visible: { opacity: 1, y: 0 }
};

const MaintenancePage = () => {
    const [requests, setRequests] = useState([]);
    const [profiles, setProfiles] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [formLoading, setFormLoading] = useState(false);
    const [currentRequest, setCurrentRequest] = useState(null);
    const { user } = useAuth();
    const userRole = user?.user_metadata?.role;

    const fetchData = async () => {
        try {
            setLoading(true);
            const [requestsResult, profilesResult] = await Promise.all([
                 supabase
                    .from('maintenance_requests')
                    .select('*, profiles:reported_by_id(full_name)')
                    .order('created_at', { ascending: false }),
                supabase
                    .from('profiles')
                    .select('id, full_name')
                    .order('full_name')
            ]);
    
            if (requestsResult.error) throw requestsResult.error;
            if (profilesResult.error) throw profilesResult.error;
    
            setRequests(requestsResult.data || []);
            setProfiles(profilesResult.data || []);
    
        } catch (error) {
            toast.error(`Failed to fetch data: ${error.message}`);
            console.error("Error fetching data:", error);
            setRequests([]);
            setProfiles([]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
    }, []);

    const openAddModal = () => {
        setCurrentRequest(null);
        setIsModalOpen(true);
    };

    const openEditModal = (request) => {
        setCurrentRequest(request);
        setIsModalOpen(true);
    };

    const handleDelete = async (requestId) => {
        if (window.confirm('Are you sure you want to delete this maintenance request?')) {
            const { error } = await supabase.from('maintenance_requests').delete().eq('id', requestId);
            if (error) {
                toast.error(error.message);
            } else {
                toast.success('Request deleted.');
                fetchData();
            }
        }
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setFormLoading(true);
        const formData = new FormData(e.target);
        const requestData = Object.fromEntries(formData.entries());

        let error;
        if (currentRequest) {
            const { error: updateError } = await supabase.from('maintenance_requests').update(requestData).eq('id', currentRequest.id);
            error = updateError;
        } else {
            const dataToInsert = { ...requestData, reported_by_id: user.id, status: 'Pending' };
            const { error: insertError } = await supabase.from('maintenance_requests').insert([dataToInsert]);
            error = insertError;
        }

        if (error) {
            toast.error(error.message);
        } else {
            toast.success(`Request ${currentRequest ? 'updated' : 'submitted'} successfully!`);
            fetchData();
            setIsModalOpen(false);
        }
        setFormLoading(false);
    };

    return (
        <>
            <PageHeader
                title="Maintenance Requests"
                buttonText="New Request"
                onButtonClick={openAddModal}
            />
            <div className="bg-base-100 dark:bg-dark-base-200 rounded-xl shadow-lg overflow-hidden transition-colors">
                <div className="overflow-x-auto">
                    <table className="min-w-full">
                        <thead className="bg-base-200 dark:bg-dark-base-300">
                            <tr>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Issue</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Room No.</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Reported By</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Date</th>
                                <th className="px-6 py-4 text-left text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Status</th>
                                <th className="px-6 py-4 text-right text-xs font-medium text-base-content-secondary dark:text-dark-base-content-secondary uppercase tracking-wider">Actions</th>
                            </tr>
                        </thead>
                        {loading ? (
                            <tbody>
                                <tr><td colSpan="6" className="text-center py-10"><Loader className="mx-auto animate-spin" /></td></tr>
                            </tbody>
                        ) : requests.length > 0 ? (
                            <motion.tbody
                                className="divide-y divide-base-200 dark:divide-dark-base-300"
                                variants={containerVariants}
                                initial="hidden"
                                animate="visible"
                            >
                                {requests.map((req) => (
                                    <motion.tr key={req.id} className="hover:bg-base-200 dark:hover:bg-dark-base-300/50 transition-colors" variants={itemVariants}>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                                            <Link to={`/maintenance/${req.id}`} className="text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">{req.issue}</Link>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{req.room_number}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{req.profiles?.full_name || 'N/A'}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{new Date(req.created_at).toLocaleDateString()}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm">
                                            <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[req.status]}`}>
                                                {req.status}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                                            {(userRole === 'Admin' || userRole === 'Staff') && (
                                                <>
                                                <button onClick={() => openEditModal(req)} className="p-2 text-primary/70 hover:text-primary dark:text-dark-primary/70 dark:hover:text-dark-primary transition-colors">
                                                    <Edit className="w-5 h-5" />
                                                </button>
                                                <button onClick={() => handleDelete(req.id)} className="p-2 text-red-500/70 hover:text-red-500 dark:text-red-500/70 dark:hover:text-red-500 transition-colors">
                                                    <Trash2 className="w-5 h-5" />
                                                </button>
                                                </>
                                            )}
                                        </td>
                                    </motion.tr>
                                ))}
                            </motion.tbody>
                        ) : (
                            <tbody>
                                <tr>
                                    <td colSpan="6">
                                        <EmptyState 
                                            icon={<Wrench className="w-full h-full" />}
                                            title="No Maintenance Requests Found"
                                            message="Submit a new request to get started or check your database policies."
                                        />
                                    </td>
                                </tr>
                            </tbody>
                        )}
                    </table>
                </div>
            </div>

            <Modal title={currentRequest ? 'Edit Maintenance Request' : 'New Maintenance Request'} isOpen={isModalOpen} onClose={() => setIsModalOpen(false)}>
                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label htmlFor="issue" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Issue Description</label>
                        <input type="text" name="issue" id="issue" defaultValue={currentRequest?.issue || ''} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                    <div>
                        <label htmlFor="room_number" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Room Number</label>
                        <input type="text" name="room_number" id="room_number" defaultValue={currentRequest?.room_number || ''} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm" />
                    </div>
                    {(userRole === 'Admin' || userRole === 'Staff') && (
                        <div>
                            <label htmlFor="reported_by_id" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Reported By</label>
                            <select id="reported_by_id" name="reported_by_id" defaultValue={currentRequest?.reported_by_id || user.id} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm">
                                <option value="">Select a user</option>
                                {profiles.map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}
                            </select>
                        </div>
                    )}
                    {currentRequest && (userRole === 'Admin' || userRole === 'Staff') && (
                         <div>
                            <label htmlFor="status" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">Status</label>
                            <select id="status" name="status" defaultValue={currentRequest?.status} required className="mt-1 block w-full rounded-md border-base-300 dark:border-dark-base-300 bg-base-100 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm">
                                <option>Pending</option>
                                <option>In Progress</option>
                                <option>Resolved</option>
                            </select>
                        </div>
                    )}
                    <div className="flex justify-end pt-4 space-x-3">
                        <button type="button" onClick={() => setIsModalOpen(false)} className="inline-flex justify-center py-2 px-4 border border-base-300 dark:border-dark-base-300 shadow-sm text-sm font-medium rounded-md text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">Cancel</button>
                        <button type="submit" disabled={formLoading} className="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-primary-content bg-primary hover:bg-primary-focus disabled:opacity-50">
                            {formLoading && <Loader className="animate-spin h-4 w-4 mr-2" />}
                            {currentRequest ? 'Save Changes' : 'Submit Request'}
                        </button>
                    </div>
                </form>
            </Modal>
        </>
    );
};

export default MaintenancePage;
