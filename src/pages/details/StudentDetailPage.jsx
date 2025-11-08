import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import DetailPageLayout from '../../components/layout/DetailPageLayout';
import DetailItem from '../../components/ui/DetailItem';
import { Loader } from 'lucide-react';
import toast from 'react-hot-toast';

const StudentDetailPage = () => {
    const { id } = useParams();
    const [student, setStudent] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchStudent = async () => {
            if (!id) return;
            setLoading(true);
            const { data, error } = await supabase
                .from('students')
                .select('*')
                .eq('id', id)
                .single();

            if (error) {
                toast.error('Student not found.');
            } else {
                setStudent(data);
            }
            setLoading(false);
        };

        fetchStudent();
    }, [id]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!student) {
        return <div className="text-center text-base-content-secondary dark:text-dark-base-content-secondary">Student not found</div>;
    }

    return (
        <DetailPageLayout title={student.full_name} backTo="/students">
            <DetailItem label="Full Name" value={student.full_name} />
            <DetailItem label="Email" value={student.email} />
            <DetailItem label="Course" value={student.course} />
            <DetailItem label="Contact" value={student.contact} />
            <DetailItem label="Joined On" value={student.created_at ? new Date(student.created_at).toLocaleDateString() : 'N/A'} />
        </DetailPageLayout>
    );
};

export default StudentDetailPage;
